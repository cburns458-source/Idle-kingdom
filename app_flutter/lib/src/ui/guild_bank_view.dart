import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'item_label.dart';
import 'quantity_sheet.dart';

/// Guild bank laid out like the personal chest: main bank and Up for grabs.
class GuildBankView extends StatelessWidget {
  const GuildBankView({
    super.key,
    required this.controller,
    required this.multiplayer,
    required this.hall,
    required this.onHallChanged,
    this.canDeposit,
    this.canWithdraw,
    this.canMove,
  });

  final GameController controller;
  final MultiplayerController multiplayer;
  final GuildHallState hall;
  final ValueChanged<GuildHallState> onHallChanged;
  final bool? canDeposit;
  final bool? canWithdraw;
  final bool? canMove;

  @override
  Widget build(BuildContext context) {
    return _GuildBankBody(
      controller: controller,
      multiplayer: multiplayer,
      hall: hall,
      onHallChanged: onHallChanged,
      canDeposit: canDeposit,
      canWithdraw: canWithdraw,
      canMove: canMove,
    );
  }
}

class _GuildBankBody extends StatefulWidget {
  const _GuildBankBody({
    required this.controller,
    required this.multiplayer,
    required this.hall,
    required this.onHallChanged,
    this.canDeposit,
    this.canWithdraw,
    this.canMove,
  });

  final GameController controller;
  final MultiplayerController multiplayer;
  final GuildHallState hall;
  final ValueChanged<GuildHallState> onHallChanged;
  final bool? canDeposit;
  final bool? canWithdraw;
  final bool? canMove;

  @override
  State<_GuildBankBody> createState() => _GuildBankBodyState();
}

class _GuildBankBodyState extends State<_GuildBankBody> {
  GameController get controller => widget.controller;
  MultiplayerController get net => widget.multiplayer;
  PlayerSave get save => controller.save;
  GuildHallState get hall => widget.hall;

  String? get _role {
    final userId = net.session?.userId;
    if (userId == null) return null;
    for (final row in net.members) {
      if (row.userId == userId) return row.role;
    }
    return null;
  }

  num get _totalLevel {
    final userId = net.session?.userId;
    if (userId == null) return totalLevel(save);
    for (final row in net.members) {
      if (row.userId == userId) return row.totalLevel;
    }
    return totalLevel(save);
  }

  bool get _canDeposit {
    if (widget.canDeposit != null) return widget.canDeposit!;
    final role = _role;
    if (role == null) return false;
    return guildMay(role, guildPermissionDeposit, net.guild?.permissions);
  }

  bool get _canWithdraw {
    if (widget.canWithdraw != null) return widget.canWithdraw!;
    final role = _role;
    if (role == null) return false;
    return guildMay(role, guildPermissionWithdraw, net.guild?.permissions) &&
        guildMayWithdrawAtLevel(_totalLevel);
  }

  bool get _canMove {
    if (widget.canMove != null) return widget.canMove!;
    final role = _role;
    if (role == null) return false;
    return guildMay(role, guildPermissionMoveUpForGrabs, net.guild?.permissions);
  }

  bool get _canTake => guildMayWithdrawAtLevel(_totalLevel);

  bool _tradeable(InventoryStack stack) {
    if (stackIsUnbankableGold(stack)) return false;
    return !bazaarItemBound(controller.db, stack.itemId);
  }

  String _stackLabel(String itemId, String? enchantmentId) {
    final item = controller.indexes.itemsById[itemId];
    final name = item?.displayName ?? itemId;
    return enchantedItemLabel(name, enchantmentName(controller.db, enchantmentId));
  }

  Future<void> _apply(GuildHallActionResult result) async {
    if (!result.ok) return;
    if (result.save != null) controller.commit(result.save!);
    if (result.hall != null) widget.onHallChanged(result.hall!);
  }

  Future<void> _deposit(int index, InventoryStack stack) async {
    if (!_canDeposit) return;
    final quantity = await askQuantity(
      context,
      title: _stackLabel(stack.itemId, stack.enchantmentId),
      confirmLabel: 'Deposit',
      max: stack.quantity.floor(),
    );
    if (quantity == null || !mounted) return;
    await _apply(await net.service.depositGuildBank(save, index, quantity));
  }

  Future<void> _withdraw(GuildBankItem row) async {
    if (!_canWithdraw) return;
    final quantity = await askQuantity(
      context,
      title: _stackLabel(row.itemId, row.enchantmentId),
      confirmLabel: 'Withdraw',
      max: row.quantity.floor(),
    );
    if (quantity == null || !mounted) return;
    await _apply(
      await net.service.withdrawGuildBank(
        save,
        row.itemId,
        quantity,
        enchantmentId: row.enchantmentId,
      ),
    );
  }

  Future<void> _take(GuildBankItem row) async {
    if (!_canTake) return;
    final quantity = await askQuantity(
      context,
      title: _stackLabel(row.itemId, row.enchantmentId),
      confirmLabel: 'Take',
      max: row.quantity.floor(),
    );
    if (quantity == null || !mounted) return;
    await _apply(
      await net.service.takeGuildBankUpForGrabs(
        save,
        row.itemId,
        quantity,
        enchantmentId: row.enchantmentId,
      ),
    );
  }

  Future<void> _move(GuildBankItem row) async {
    if (!_canMove) return;
    final quantity = await askQuantity(
      context,
      title: _stackLabel(row.itemId, row.enchantmentId),
      confirmLabel: 'Move',
      max: row.quantity.floor(),
    );
    if (quantity == null || !mounted) return;
    await _apply(
      await net.service.moveGuildBankToUpForGrabs(
        save,
        row.itemId,
        quantity,
        enchantmentId: row.enchantmentId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final main = hall.bank.section(guildBankSectionMain);
    final grabs = hall.bank.section(guildBankSectionUpForGrabs);
    final bag = <(int, InventoryStack)>[
      for (final entry in save.inventory.indexed)
        if (_tradeable(entry.$2)) (entry.$1, entry.$2),
    ];
    return ListView(
      children: [
        const Text('Bank', style: TextStyle(fontWeight: FontWeight.w400)),
        const SizedBox(height: 6),
        for (final row in main)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: DockRow(
              title: _stackLabel(row.itemId, row.enchantmentId),
              lines: [MutedText('×${formatThousands(row.quantity)}')],
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GameButton(
                    key: Key('guild-bank-out-${row.id}'),
                    label: 'Out',
                    compact: true,
                    onPressed: _canWithdraw ? () => _withdraw(row) : null,
                  ),
                  const SizedBox(width: 4),
                  GameButton(
                    key: Key('guild-bank-move-${row.id}'),
                    label: 'Move',
                    compact: true,
                    onPressed: _canMove ? () => _move(row) : null,
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 10),
        const Text('Up for grabs', style: TextStyle(fontWeight: FontWeight.w400)),
        const SizedBox(height: 6),
        for (final row in grabs)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: DockRow(
              title: _stackLabel(row.itemId, row.enchantmentId),
              lines: [MutedText('×${formatThousands(row.quantity)}')],
              trailing: GameButton(
                key: Key('guild-bank-take-${row.id}'),
                label: 'Take',
                compact: true,
                onPressed: _canTake ? () => _take(row) : null,
              ),
            ),
          ),
        const SizedBox(height: 10),
        const Text('Bag', style: TextStyle(fontWeight: FontWeight.w400)),
        const SizedBox(height: 6),
        for (final entry in bag)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: DockRow(
              title: _stackLabel(entry.$2.itemId, entry.$2.enchantmentId),
              lines: [MutedText('×${formatThousands(entry.$2.quantity)}')],
              trailing: GameButton(
                key: Key('guild-bank-in-${entry.$1}'),
                label: 'In',
                compact: true,
                onPressed: _canDeposit ? () => _deposit(entry.$1, entry.$2) : null,
              ),
            ),
          ),
      ],
    );
  }
}
