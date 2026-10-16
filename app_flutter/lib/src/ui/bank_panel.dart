import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'dialogue_text.dart';
import 'game_popup.dart';
import 'floating_slot.dart';
import 'format.dart';
import 'item_icon.dart';
import 'item_label.dart';
import 'quantity_sheet.dart';

/// Player-facing `no_room` copy for this chest. Stack-full shares the bag line.
String bankNoRoomMessage(NoRoom? noRoom, {int? slotsNeeded}) {
  if (noRoom?.reason == 'stack_full') return DialogueText.stackFull;
  final n = slotsNeeded ?? noRoom?.slotsNeeded ?? 1;
  if (noRoom?.target == 'bank') {
    return 'Your bank is full. Make room for ${DialogueText.moreItems(n)} and try again.';
  }
  return DialogueText.bagFull(n);
}

/// Town and Citadel vault: stored stacks on the left, bag on the right.
class BankPanel extends StatefulWidget {
  const BankPanel({super.key, required this.controller, this.multiplayer, this.onClose});

  final GameController controller;
  final MultiplayerController? multiplayer;
  final VoidCallback? onClose;

  @override
  State<BankPanel> createState() => _BankPanelState();
}

class _BankPanelState extends State<BankPanel> {
  final TextEditingController _search = TextEditingController();
  late InventorySorter _sorter = InventorySorter(widget.controller.db);
  String? _error;
  bool _guildTab = false;
  GuildHallState? _guildHall;

  List<({int index, InventoryStack stack})>? _cachedBag;
  List<({int index, InventoryStack stack})>? _cachedChest;
  int? _bagInventoryIdentity;
  int? _bagInventoryLength;
  int? _chestBankIdentity;
  int? _chestBankLength;
  String? _cacheSearch;

  GameController get controller => widget.controller;
  PlayerSave get save => controller.save;

  @override
  void initState() {
    super.initState();
    _loadGuildHall();
  }

  Future<void> _loadGuildHall() async {
    final net = widget.multiplayer;
    final guildId = net?.guildId;
    if (net == null || guildId == null) return;
    final hall = await net.service.guildHall(guildId);
    if (!mounted) return;
    setState(() => _guildHall = hall);
  }

  @override
  void didUpdateWidget(BankPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _sorter = InventorySorter(widget.controller.db);
      _invalidateCaches();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _invalidateCaches() {
    _cachedBag = null;
    _cachedChest = null;
    _bagInventoryIdentity = null;
    _bagInventoryLength = null;
    _chestBankIdentity = null;
    _chestBankLength = null;
    _cacheSearch = null;
  }

  bool _matches(InventoryStack stack) {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return true;
    final item = controller.indexes.itemsById[stack.itemId];
    final name = (item?.displayName ?? stack.itemId).toLowerCase();
    return name.contains(query) || stack.itemId.toLowerCase().contains(query);
  }

  List<({int index, InventoryStack stack})> _bagRows(PlayerSave save) {
    final identity = identityHashCode(save.inventory);
    final length = save.inventory.length;
    final search = _search.text;
    if (_cachedBag != null &&
        _bagInventoryIdentity == identity &&
        _bagInventoryLength == length &&
        _cacheSearch == search) {
      return _cachedBag!;
    }
    final bag = <({int index, InventoryStack stack})>[
      for (final entry in save.inventory.indexed)
        if (!stackIsUnbankable(entry.$2) && _matches(entry.$2)) (index: entry.$1, stack: entry.$2),
    ]..sort((a, b) => _sorter.compareGrouped(a.stack, b.stack, a.index, b.index));
    _cachedBag = bag;
    _bagInventoryIdentity = identity;
    _bagInventoryLength = length;
    _cacheSearch = search;
    return bag;
  }

  List<({int index, InventoryStack stack})> _chestRows(PlayerSave save) {
    final stacks = bankStacks(save);
    final identity = identityHashCode(stacks);
    final length = stacks.length;
    final search = _search.text;
    if (_cachedChest != null &&
        _chestBankIdentity == identity &&
        _chestBankLength == length &&
        _cacheSearch == search) {
      return _cachedChest!;
    }
    final chest = <({int index, InventoryStack stack})>[
      for (final entry in stacks.indexed)
        if (_matches(entry.$2)) (index: entry.$1, stack: entry.$2),
    ];
    _cachedChest = chest;
    _chestBankIdentity = identity;
    _chestBankLength = length;
    _cacheSearch = search;
    return chest;
  }

  String _stackLabel(InventoryStack stack) {
    final item = controller.indexes.itemsById[stack.itemId];
    final name = item?.displayName ?? stack.itemId;
    return enchantedItemLabel(name, enchantmentName(controller.db, stack.enchantmentId));
  }

  Future<void> _deposit(int index, InventoryStack stack) async {
    final quantity = await askQuantity(
      context,
      subtitle: 'From the bag',
      title: _stackLabel(stack),
      details: [
        'In bag: ${formatThousands(stack.quantity)}',
        'Bank slots free: ${formatThousands(bankSlotsFree(save))}',
      ],
      confirmLabel: 'Deposit',
      max: stack.quantity.floor(),
    );
    if (quantity == null || !mounted) return;
    final result = depositToBank(save, index, quantity);
    if (!result.ok) {
      if (result.code == 'no_room') {
        setState(() => _error = null);
        await showGameAlert(context: context, message: bankNoRoomMessage(result.noRoom));
        return;
      }
      setState(() => _error = result.reason);
      return;
    }
    controller.commitLoadout(
      result.save!,
      command: 'bank_deposit',
      args: <String, Object?>{
        'inventoryIndex': index,
        'quantity': quantity,
        'itemId': stack.itemId,
        if (stack.enchantmentId != null && stack.enchantmentId!.isNotEmpty)
          'enchantmentId': stack.enchantmentId,
      },
    );
    _invalidateCaches();
    setState(() => _error = null);
  }

  Future<void> _withdraw(int index, InventoryStack stack) async {
    final quantity = await askQuantity(
      context,
      subtitle: 'From the chest',
      title: _stackLabel(stack),
      details: [
        'In bank: ${formatThousands(stack.quantity)}',
        'Bag slots free: ${formatThousands(inventorySlotsFree(save))}',
      ],
      confirmLabel: 'Withdraw',
      max: stack.quantity.floor(),
    );
    if (quantity == null || !mounted) return;
    final result = withdrawFromBank(save, index, quantity);
    if (!result.ok) {
      if (result.code == 'no_room') {
        setState(() => _error = null);
        await showGameAlert(context: context, message: bankNoRoomMessage(result.noRoom));
        return;
      }
      setState(() => _error = result.reason);
      return;
    }
    controller.commitLoadout(
      result.save!,
      command: 'bank_withdraw',
      args: <String, Object?>{
        'bankIndex': index,
        'quantity': quantity,
        'itemId': stack.itemId,
        if (stack.enchantmentId != null && stack.enchantmentId!.isNotEmpty)
          'enchantmentId': stack.enchantmentId,
      },
    );
    _invalidateCaches();
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final bag = _bagRows(save);
    final chest = _chestRows(save);
    final bankLen = bankStacks(save).length;

    return GamePanel(
      framed: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Bank',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: GameFont.l, fontWeight: FontWeight.w400),
                ),
              ),
              GoldAmount(
                amount: save.gold,
                style: const TextStyle(color: Palette.gold),
              ),
              if (widget.onClose != null) GameCloseButton(onPressed: widget.onClose),
            ],
          ),
          MutedText(
            'Bag ${formatThousands(save.inventory.length)}/$inventorySlotLimit · '
            'Bank ${formatThousands(bankLen)}/$bankSlotLimit',
          ),
          if (_guildHall?.bankUnlocked == true) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: GameButton(
                    label: 'Personal',
                    tone: _guildTab ? GameButtonTone.secondary : GameButtonTone.primary,
                    onPressed: () => setState(() => _guildTab = false),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: GameButton(
                    label: 'Guild',
                    tone: _guildTab ? GameButtonTone.primary : GameButtonTone.secondary,
                    onPressed: () => setState(() => _guildTab = true),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _search,
            decoration: const InputDecoration(hintText: 'Search items', isDense: true),
            onChanged: (_) {
              _invalidateCaches();
              setState(() {});
            },
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 6),
            Text(
              error,
              style: const TextStyle(color: Palette.danger, fontSize: GameFont.s),
            ),
          ],
          const SizedBox(height: 10),
          Expanded(
            child: _guildTab && _guildHall != null
                ? _guildBankBody(_guildHall!)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _Column(
                          heading: 'Bank',
                          empty: bankLen == 0
                              ? 'The chest is empty.'
                              : 'Nothing in the bank matches.',
                          itemCount: chest.length,
                          itemBuilder: (context, i) {
                            final row = chest[i];
                            return _tileFor(
                              key: ValueKey('bank-${row.index}'),
                              stack: row.stack,
                              onTap: () => _withdraw(row.index, row.stack),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: _Column(
                          heading: 'Bag',
                          empty: save.inventory.isEmpty
                              ? 'The bag is empty.'
                              : bag.isEmpty && save.inventory.every(stackIsUnbankableGold)
                              ? 'Nothing in the bag to deposit.'
                              : 'Nothing in the bag matches.',
                          itemCount: bag.length,
                          itemBuilder: (context, i) {
                            final row = bag[i];
                            return _tileFor(
                              key: ValueKey('bag-${row.index}'),
                              stack: row.stack,
                              onTap: () => _deposit(row.index, row.stack),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _guildBankBody(GuildHallState hall) {
    final net = widget.multiplayer;
    final userId = net?.session?.userId;
    String? role;
    num total = 1;
    for (final row in net?.members ?? const <GuildMember>[]) {
      if (row.userId == userId) {
        role = row.role;
        total = row.totalLevel;
      }
    }
    final table = net?.guild?.permissions ?? defaultGuildPermissionTable();
    final canDeposit = role != null && guildMay(role, guildPermissionDeposit, table);
    final canWithdraw =
        role != null &&
        guildMay(role, guildPermissionWithdraw, table) &&
        guildMayWithdrawAtLevel(total);
    final canMove = role != null && guildMay(role, guildPermissionMoveUpForGrabs, table);
    final main = hall.bank.section(guildBankSectionMain);
    final grabs = hall.bank.section(guildBankSectionUpForGrabs);
    return ListView(
      children: [
        const Text('Main', style: TextStyle(fontWeight: FontWeight.w400)),
        const MutedText('Tradeable items. Under total level 200 can deposit but not withdraw.'),
        if (main.isEmpty)
          const MutedText('Empty.')
        else
          for (final row in main)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: DockRow(
                title: _stackLabel(
                  InventoryStack(
                    itemId: row.itemId,
                    quantity: row.quantity,
                    enchantmentId: row.enchantmentId,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GameButton(
                      label: 'Out',
                      compact: true,
                      onPressed: canWithdraw ? () => _guildWithdraw(row, fromGrabs: false) : null,
                    ),
                    const SizedBox(width: 4),
                    GameButton(
                      label: 'Up for grabs',
                      compact: true,
                      onPressed: canMove ? () => _guildMove(row) : null,
                    ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 10),
        const Text('Up for grabs', style: TextStyle(fontWeight: FontWeight.w400)),
        const MutedText('Anyone in the guild can take these.'),
        if (grabs.isEmpty)
          const MutedText('Empty.')
        else
          for (final row in grabs)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: DockRow(
                title: _stackLabel(
                  InventoryStack(
                    itemId: row.itemId,
                    quantity: row.quantity,
                    enchantmentId: row.enchantmentId,
                  ),
                ),
                trailing: GameButton(
                  label: 'Take',
                  compact: true,
                  onPressed: () => _guildWithdraw(row, fromGrabs: true),
                ),
              ),
            ),
        const SizedBox(height: 10),
        const Text('Bag', style: TextStyle(fontWeight: FontWeight.w400)),
        for (final entry in save.inventory.indexed)
          if (!stackIsUnbankableGold(entry.$2))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: DockRow(
                title: _stackLabel(entry.$2),
                trailing: GameButton(
                  label: 'In',
                  compact: true,
                  onPressed: canDeposit ? () => _guildDeposit(entry.$1, entry.$2) : null,
                ),
              ),
            ),
      ],
    );
  }

  Future<void> _guildDeposit(int index, InventoryStack stack) async {
    final net = widget.multiplayer;
    if (net == null) return;
    final quantity = await askQuantity(
      context,
      title: _stackLabel(stack),
      subtitle: 'Into the guild bank',
      confirmLabel: 'Deposit',
      max: stack.quantity.floor(),
    );
    if (quantity == null || !mounted) return;
    final result = await net.service.depositGuildBank(save, index, quantity);
    if (!result.ok) {
      setState(() => _error = result.reason);
      return;
    }
    if (result.save != null) controller.commit(result.save!);
    setState(() {
      _guildHall = result.hall;
      _error = null;
    });
  }

  Future<void> _guildWithdraw(GuildBankItem row, {required bool fromGrabs}) async {
    final net = widget.multiplayer;
    if (net == null) return;
    final quantity = await askQuantity(
      context,
      title: _stackLabel(
        InventoryStack(
          itemId: row.itemId,
          quantity: row.quantity,
          enchantmentId: row.enchantmentId,
        ),
      ),
      subtitle: fromGrabs ? 'From Up for grabs' : 'From the guild bank',
      confirmLabel: fromGrabs ? 'Take' : 'Withdraw',
      max: row.quantity.floor(),
    );
    if (quantity == null || !mounted) return;
    final result = fromGrabs
        ? await net.service.takeGuildBankUpForGrabs(
            save,
            row.itemId,
            quantity,
            enchantmentId: row.enchantmentId,
          )
        : await net.service.withdrawGuildBank(
            save,
            row.itemId,
            quantity,
            enchantmentId: row.enchantmentId,
          );
    if (!result.ok) {
      setState(() => _error = result.reason);
      return;
    }
    if (result.save != null) controller.commit(result.save!);
    setState(() {
      _guildHall = result.hall;
      _error = null;
    });
  }

  Future<void> _guildMove(GuildBankItem row) async {
    final net = widget.multiplayer;
    if (net == null) return;
    final quantity = await askQuantity(
      context,
      title: _stackLabel(
        InventoryStack(
          itemId: row.itemId,
          quantity: row.quantity,
          enchantmentId: row.enchantmentId,
        ),
      ),
      subtitle: 'Move to Up for grabs',
      confirmLabel: 'Move',
      max: row.quantity.floor(),
    );
    if (quantity == null || !mounted) return;
    final result = await net.service.moveGuildBankToUpForGrabs(
      save,
      row.itemId,
      quantity,
      enchantmentId: row.enchantmentId,
    );
    if (!result.ok) {
      setState(() => _error = result.reason);
      return;
    }
    if (result.save != null) controller.commit(result.save!);
    setState(() {
      _guildHall = result.hall;
      _error = null;
    });
  }

  Widget _tileFor({required Key key, required InventoryStack stack, required VoidCallback onTap}) {
    final item = controller.indexes.itemsById[stack.itemId];
    final name = item?.displayName ?? stack.itemId;
    final enchantment = enchantmentName(controller.db, stack.enchantmentId);
    final favorite = stack.favorite == true;
    return FloatingItemSlot(
      key: key,
      tooltip: itemTileTooltip(name, enchantment),
      padding: const EdgeInsets.fromLTRB(3, 5, 3, 4),
      onTap: onTap,
      child: Stack(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ItemIcon(item: item, size: 36),
              const SizedBox(height: 2),
              Text(
                '×${formatThousands(stack.quantity)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: GameFont.xs, color: Palette.muted, height: 1.1),
              ),
            ],
          ),
          if (enchantment != null || favorite)
            Positioned(
              right: 0,
              top: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (enchantment != null)
                    const Text(
                      '★',
                      style: TextStyle(fontSize: GameFont.s, color: Palette.softGreen),
                    ),
                  if (favorite) const Icon(Icons.favorite, size: 14, color: Palette.gold),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.heading,
    required this.empty,
    required this.itemCount,
    required this.itemBuilder,
  });

  final String heading;
  final String empty;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          heading,
          style: const TextStyle(fontSize: GameFont.m, fontWeight: FontWeight.w400),
        ),
        const SizedBox(height: 5),
        Expanded(
          child: FloatingItemWell(
            child: itemCount == 0
                ? Align(
                    alignment: Alignment.topLeft,
                    child: MutedText(empty, color: Palette.muted),
                  )
                : RepaintBoundary(
                    child: GridView.builder(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 78,
                        mainAxisSpacing: 5,
                        crossAxisSpacing: 5,
                        childAspectRatio: 1,
                      ),
                      itemCount: itemCount,
                      itemBuilder: itemBuilder,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
