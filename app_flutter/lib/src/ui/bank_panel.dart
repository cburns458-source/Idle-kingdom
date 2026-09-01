import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'item_icon.dart';
import 'quantity_sheet.dart';

/// Town and Citadel vault: stored stacks on the left, bag on the right.
class BankPanel extends StatefulWidget {
  const BankPanel({super.key, required this.controller, this.onClose});

  final GameController controller;
  final VoidCallback? onClose;

  @override
  State<BankPanel> createState() => _BankPanelState();
}

class _BankPanelState extends State<BankPanel> {
  final TextEditingController _search = TextEditingController();
  late InventorySorter _sorter = InventorySorter(widget.controller.db);
  String? _error;

  GameController get controller => widget.controller;
  PlayerSave get save => controller.save;

  @override
  void didUpdateWidget(BankPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _sorter = InventorySorter(widget.controller.db);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(InventoryStack stack) {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return true;
    final item = controller.indexes.itemsById[stack.itemId];
    final name = (item?.displayName ?? stack.itemId).toLowerCase();
    return name.contains(query) || stack.itemId.toLowerCase().contains(query);
  }

  Future<void> _deposit(int index, InventoryStack stack) async {
    final item = controller.indexes.itemsById[stack.itemId];
    final name = item?.displayName ?? stack.itemId;
    final quantity = await askQuantity(
      context,
      subtitle: 'From the bag',
      title: name,
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
      setState(() => _error = result.reason);
      return;
    }
    controller.commitLoadout(result.save!);
    setState(() => _error = null);
  }

  Future<void> _withdraw(int index, InventoryStack stack) async {
    final item = controller.indexes.itemsById[stack.itemId];
    final name = item?.displayName ?? stack.itemId;
    final quantity = await askQuantity(
      context,
      subtitle: 'From the chest',
      title: name,
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
      setState(() => _error = result.reason);
      return;
    }
    controller.commitLoadout(result.save!);
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final bag = <({int index, InventoryStack stack})>[
      for (final entry in save.inventory.indexed)
        if (!stackIsUnbankableGold(entry.$2) && _matches(entry.$2))
          (index: entry.$1, stack: entry.$2),
    ]..sort((a, b) => _sorter.compareGrouped(a.stack, b.stack, a.index, b.index));
    final chest = <({int index, InventoryStack stack})>[
      for (final entry in bankStacks(save).indexed)
        if (_matches(entry.$2)) (index: entry.$1, stack: entry.$2),
    ];

    return GamePanel(
      framed: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Bank', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w400)),
              ),
              GoldAmount(
                amount: save.gold,
                style: const TextStyle(color: Palette.gold),
              ),
              if (widget.onClose != null)
                GameIconButton(icon: Icons.close, tooltip: 'Close', onPressed: widget.onClose),
            ],
          ),
          MutedText(
            'Bag ${formatThousands(save.inventory.length)}/$inventorySlotLimit · '
            'Bank ${formatThousands(bankStacks(save).length)}/$inventorySlotLimit',
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _search,
            decoration: const InputDecoration(hintText: 'Search items', isDense: true),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Column(
                  heading: 'Bank',
                  empty: bankStacks(save).isEmpty
                      ? 'The chest is empty.'
                      : 'Nothing in the bank matches.',
                  tiles: [
                    for (final row in chest)
                      _tileFor(
                        key: ValueKey('bank-${row.index}'),
                        stack: row.stack,
                        onTap: () => _withdraw(row.index, row.stack),
                      ),
                  ],
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
                  tiles: [
                    for (final row in bag)
                      _tileFor(
                        key: ValueKey('bag-${row.index}'),
                        stack: row.stack,
                        onTap: () => _deposit(row.index, row.stack),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 6),
            Text(error, style: const TextStyle(color: Palette.danger, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _tileFor({required Key key, required InventoryStack stack, required VoidCallback onTap}) {
    final item = controller.indexes.itemsById[stack.itemId];
    final name = item?.displayName ?? stack.itemId;
    return Tooltip(
      message: name,
      child: PixelInkPlate(
        key: key,
        onTap: onTap,
        step: PixelChrome.stepTight,
        fillColor: stack.favorite == true
            ? Color.lerp(UiChrome.of(context).slot, Palette.gold, 0.18)!
            : UiChrome.of(context).slot,
        material: PixelPlateMaterial.none,
        strokeWidth: stack.favorite == true ? 2.5 : 2,
        selected: stack.favorite == true,
        shadow: false,
        padding: const EdgeInsets.fromLTRB(3, 5, 3, 4),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: Palette.parchmentText),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ItemIcon(item: item, size: 36),
              const SizedBox(height: 2),
              Text(
                '×${formatThousands(stack.quantity)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5, color: Palette.muted, height: 1.1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({required this.heading, required this.empty, required this.tiles});

  final String heading;
  final String empty;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(heading, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w400)),
        const SizedBox(height: 5),
        if (tiles.isEmpty)
          MutedText(empty)
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 256),
            child: GridView.extent(
              maxCrossAxisExtent: 78,
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              mainAxisSpacing: 5,
              crossAxisSpacing: 5,
              childAspectRatio: 1,
              children: tiles,
            ),
          ),
      ],
    );
  }
}
