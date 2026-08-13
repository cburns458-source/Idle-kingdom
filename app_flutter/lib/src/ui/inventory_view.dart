import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'item_detail_sheet.dart';
import 'item_icon.dart';

/// Paper-doll order: 4 columns × 4 rows, spells down the right-hand column.
const List<String> equipmentGridOrder = <String>[
  'SLOT-0008', // Neck
  'SLOT-0003', // Helmet
  'SLOT-0010', // Back
  'SLOT-0013', // Spell 1
  'SLOT-0001', // Weapon / Tool
  'SLOT-0004', // Chest
  'SLOT-0002', // Off-hand / Shield
  'SLOT-0014', // Spell 2
  'SLOT-0009', // Ring
  'SLOT-0005', // Legs
  'SLOT-0007', // Gloves
  'SLOT-0015', // Spell 3
  'SLOT-0011', // Food
  'SLOT-0006', // Boots
  'SLOT-0012', // Potion
  'SLOT-0016', // Spell 4
];

enum _InventoryTab { items, equipment }

/// The bag and the worn gear, with the combat numbers they add up to.
class InventoryView extends StatefulWidget {
  const InventoryView({super.key, required this.controller});

  final GameController controller;

  @override
  State<InventoryView> createState() => _InventoryViewState();
}

class _InventoryViewState extends State<InventoryView> {
  _InventoryTab _tab = _InventoryTab.items;
  String? _message;

  /// Non-null while picking stacks to sell; the set is the chosen indexes.
  Set<int>? _selling;

  GameController get controller => widget.controller;
  GameDatabase get db => controller.db;
  PlayerSave get save => controller.save;

  void _exitSellMode() {
    setState(() {
      _selling = null;
      _message = null;
    });
  }

  void _equipAt(int index) {
    final result = equipInventoryIndex(db, save, index);
    if (!result.ok) {
      setState(() => _message = result.reason);
      return;
    }
    setState(() => _message = null);
    controller.commitLoadout(result.save!);
  }

  void _unequip(String slotId) {
    final result = unequipSlot(save, slotId);
    if (!result.ok) {
      setState(() => _message = result.reason);
      return;
    }
    setState(() => _message = null);
    controller.commitLoadout(result.save!);
  }

  void _toggleFavorite(int index) {
    final next = toggleInventoryFavorite(save, index);
    if (next == null) return;
    setState(() {
      _message = null;
      // Favorites sort to the front, so any sell selection now points elsewhere.
      if (_selling != null) _selling = <int>{};
    });
    controller.commitLoadout(next);
  }

  void _toggleSelection(int index) {
    final stack = save.inventory[index];
    if (isFavoriteStack(stack)) {
      setState(() => _message = 'Favorited items cannot be sold. Unfavorite them first.');
      return;
    }
    setState(() {
      final selected = _selling!.toSet();
      if (!selected.remove(index)) selected.add(index);
      _selling = selected;
    });
  }

  /// What the current selection is worth, skipping what cannot be sold.
  num get _selectedGold {
    return _selling!.fold<num>(0, (sum, index) {
      if (index >= save.inventory.length) return sum;
      final stack = save.inventory[index];
      if (stack.enchantmentId != null || isFavoriteStack(stack)) return sum;
      final priced = sellPriceAtLocation(db, save, stack.itemId);
      if (priced == null) return sum;
      return sum + priced.unitPrice * stack.quantity;
    });
  }

  Future<void> _confirmSell() async {
    final selected = _selling;
    if (selected == null || selected.isEmpty) return;
    final gold = _selectedGold;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Palette.parchmentDeep,
        title: const Text('Sell items?'),
        content: Text(
          'Sell ${pluralize(selected.length, 'stack')} for ${formatThousands(gold)} gold.',
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep items'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm sell'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final result = sellInventoryIndexes(db, save, selected);
    if (!result.ok) {
      setState(() {
        _message = result.reason;
        _selling = <int>{};
      });
      return;
    }
    controller.commitLoadout(result.save!);
    setState(() {
      _message = result.message;
      _selling = null;
    });
  }

  void _showDetail({InventoryStack? stack, EquippedStack? equipped, String? slotId}) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => ItemDetailSheet(
        controller: controller,
        itemId: stack?.itemId ?? equipped?.itemId,
        quantity: stack?.quantity ?? equipped?.quantity ?? 0,
        enchantmentId: stack?.enchantmentId ?? equipped?.enchantmentId,
        slotId: slotId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(),
        Expanded(child: _tab == _InventoryTab.items ? _bag() : _paperDoll()),
      ],
    );
  }

  Widget _header() {
    final damage = playerDamageRange(db, save);
    final offhand = playerOffhandDamageRange(db, save);
    final maxHp = playerMaxHp(db, save);
    final selling = _selling;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Inventory',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              MutedText('${inventorySlotCount(save)} / $inventorySlotLimit slots'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _Stat(
                label: 'Damage',
                value: offhand == null
                    ? '${damage.min}–${damage.max}'
                    : '${damage.min}–${damage.max} · OH ${offhand.min}–${offhand.max}',
              ),
              _Stat(label: 'Health', value: '${save.currentHp}/$maxHp'),
              _Stat(label: 'DR', value: '${playerDamageReduction(db, save)}'),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<_InventoryTab>(
            segments: const [
              ButtonSegment(value: _InventoryTab.items, label: Text('Items')),
              ButtonSegment(value: _InventoryTab.equipment, label: Text('Equipment')),
            ],
            selected: {_tab},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => setState(() {
              _tab = selection.first;
              _selling = null;
              _message = null;
            }),
          ),
          if (selling != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton(onPressed: _exitSellMode, child: const Text('Cancel')),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: selling.isEmpty ? null : _confirmSell,
                    child: Text(
                      selling.isEmpty
                          ? 'Sell selected'
                          : 'Sell selected (${formatThousands(_selectedGold)}g)',
                    ),
                  ),
                ),
              ],
            ),
          ] else if (_tab == _InventoryTab.items) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: save.inventory.isEmpty
                    ? null
                    : () => setState(() {
                        _selling = <int>{};
                        _message = null;
                      }),
                child: const Text('Sell items'),
              ),
            ),
          ],
          if (_message case final message?) ...[
            const SizedBox(height: 6),
            Text(message, style: const TextStyle(fontSize: 12, color: Palette.danger)),
          ],
        ],
      ),
    );
  }

  Widget _bag() {
    if (save.inventory.isEmpty) {
      return const Center(child: MutedText('No items yet. Fight or gather to fill this grid.'));
    }
    final selling = _selling;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 84,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: save.inventory.length,
          itemBuilder: (context, index) {
            final stack = save.inventory[index];
            final item = controller.indexes.itemsById[stack.itemId];
            final equippable = equipmentForItemId(db, stack.itemId)?.slotId != null;
            return _ItemTile(
              item: item,
              quantity: stack.quantity,
              enchanted: stack.enchantmentId != null,
              favorite: isFavoriteStack(stack),
              selected: selling?.contains(index) ?? false,
              selecting: selling != null,
              onTap: () {
                if (selling != null) {
                  _toggleSelection(index);
                } else if (equippable) {
                  _equipAt(index);
                } else {
                  _showDetail(stack: stack);
                }
              },
              onLongPress: () => _showDetail(stack: stack),
              onToggleFavorite: () => _toggleFavorite(index),
            );
          },
        ),
        const SizedBox(height: 8),
        MutedText(
          selling != null
              ? 'Tap items to select them, then confirm. Favorited items cannot be sold. '
                    'Shops pay full value; selling in the field pays half.'
              : 'Tap the heart to keep an item safe from selling. Tap gear to equip it, '
                    'and hold anything for its details.',
        ),
      ],
    );
  }

  Widget _paperDoll() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [for (final slotId in equipmentGridOrder) _slotTile(slotId)],
        ),
        const SizedBox(height: 8),
        const MutedText(
          'Equipped spells are always active, and duplicates stack. Tap worn gear to take it '
          'off, or hold a slot for what it does.',
        ),
      ],
    );
  }

  Widget _slotTile(String slotId) {
    final stack = save.equipment.slots[slotId];
    final slot = db.equipmentSlots.where((row) => row.slotId == slotId).firstOrNull;
    if (stack == null) {
      return GamePanel(
        padding: const EdgeInsets.all(4),
        onTap: () => _showDetail(slotId: slotId),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SlotGlyph(slotId: slotId, size: 30),
            const SizedBox(height: 2),
            Flexible(
              child: Text(
                slot?.displayName ?? slotId,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9, color: Color(0x80F4E7C8)),
              ),
            ),
          ],
        ),
      );
    }

    return _ItemTile(
      item: controller.indexes.itemsById[stack.itemId],
      quantity: stack.quantity,
      enchanted: stack.enchantmentId != null,
      favorite: false,
      selected: false,
      selecting: false,
      onTap: () => _unequip(slotId),
      onLongPress: () => _showDetail(equipped: stack, slotId: slotId),
      onToggleFavorite: null,
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MutedText(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// One bag or slot tile: art, count, and the marks for enchanted and favorite.
class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.quantity,
    required this.enchanted,
    required this.favorite,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleFavorite,
  });

  final ItemRow? item;
  final num quantity;
  final bool enchanted;
  final bool favorite;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: selected ? const Color(0x33D4AF37) : const Color(0x66231710),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? Palette.gold
                : enchanted
                ? Palette.softGreen
                : Palette.edge,
            width: selected ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ItemIcon(item: item, size: 30),
                  Flexible(
                    child: Text(
                      item?.displayName ?? '?',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 9, color: Color(0xB3F4E7C8)),
                    ),
                  ),
                ],
              ),
            ),
            if (!enchanted && quantity > 1)
              Positioned(
                right: 0,
                bottom: 0,
                child: Text(
                  '${quantity.round()}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            if (enchanted)
              const Positioned(
                left: 0,
                top: 0,
                child: Text('★', style: TextStyle(fontSize: 11, color: Palette.softGreen)),
              ),
            if (selected)
              const Positioned(
                right: 0,
                top: 0,
                child: Icon(Icons.check, size: 14, color: Palette.gold),
              ),
            if (onToggleFavorite != null && !selecting)
              Positioned(
                left: -6,
                bottom: -6,
                child: IconButton(
                  onPressed: onToggleFavorite,
                  visualDensity: VisualDensity.compact,
                  iconSize: 14,
                  tooltip: favorite ? 'Unfavorite' : 'Favorite',
                  icon: Icon(
                    favorite ? Icons.favorite : Icons.favorite_border,
                    color: favorite ? Palette.gold : const Color(0x80F4E7C8),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
