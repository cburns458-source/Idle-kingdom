import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'game_popup.dart';
import 'item_icon.dart';

/// Everything known about one item: stats, enchantment, spell effect, sell value.
///
/// Stands in for the React client's hold-to-reveal tooltip, which does not
/// translate to a phone. Opened for a bag stack, a worn stack, or an empty slot,
/// whichever the caller passes.
class ItemDetailSheet extends StatelessWidget {
  const ItemDetailSheet({
    super.key,
    required this.controller,
    required this.itemId,
    required this.quantity,
    this.enchantmentId,
    this.slotId,
    this.onEquip,
    this.onEat,
    this.eatEnabled = true,
  });

  final GameController controller;

  /// Null for an empty equipment slot, where only the slot itself is described.
  final String? itemId;
  final num quantity;
  final String? enchantmentId;
  final String? slotId;

  /// Equips this bag piece. Omitted for worn gear, empty slots, and items that
  /// cannot be equipped.
  final VoidCallback? onEquip;

  /// Eats this food immediately. Hidden when the Eat button is off in Settings.
  final VoidCallback? onEat;

  /// False during combat so Eat stays visible but cannot fire.
  final bool eatEnabled;

  @override
  Widget build(BuildContext context) {
    final db = controller.db;
    final id = itemId;
    final item = id == null ? null : controller.indexes.itemsById[id];
    final slot = slotId == null
        ? null
        : db.equipmentSlots.where((row) => row.slotId == slotId).firstOrNull;

    final lines = <String>[
      if (id != null) ...equipmentTooltipStatLines(equipmentForItemId(db, id), db),
      ...enchantmentTooltipLines(db, enchantmentId),
      if (id != null && isSpellItem(db, id)) ...spellTooltipLines(db, item, id),
      if (id == null && slotId != null && isSpellSlotId(slotId!))
        'Equip a spell from your bag. Spells are always active.',
    ];

    final description = item?.description;
    final priced = id == null ? null : sellPriceAtLocation(db, controller.save, id);

    return GamePopupCard(
      child: GamePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (id == null && slotId != null)
                  SlotGlyph(slotId: slotId!, size: 38)
                else
                  ItemIcon(item: item, size: 38),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item?.displayName ?? slot?.displayName ?? id ?? 'Empty slot',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
                      ),
                      if (quantity > 1) MutedText('×${formatThousands(quantity)}'),
                      if (id != null && slot != null) MutedText('Worn: ${slot.displayName}'),
                    ],
                  ),
                ),
              ],
            ),
            if (description is String && description.isNotEmpty) ...[
              const SizedBox(height: 8),
              MutedText(description),
            ],
            if (lines.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(line, style: const TextStyle(fontSize: 13)),
                ),
            ],
            if (priced != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  MutedText(priced.shopId == null ? 'Field value each' : 'Shop pays each'),
                  const SizedBox(width: 6),
                  GoldAmount(amount: priced.unitPrice, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onEat != null) ...[
                  GameButton(
                    label: 'Eat',
                    onPressed: eatEnabled
                        ? () {
                            Navigator.of(context).pop();
                            onEat!();
                          }
                        : null,
                  ),
                  const SizedBox(width: 8),
                ],
                if (onEquip != null) ...[
                  GameButton(
                    label: 'Equip',
                    onPressed: () {
                      Navigator.of(context).pop();
                      onEquip!();
                    },
                  ),
                  const SizedBox(width: 8),
                ],
                GameButton(
                  label: 'Close',
                  tone: GameButtonTone.secondary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
