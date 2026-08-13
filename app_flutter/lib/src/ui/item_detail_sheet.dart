import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'format.dart';
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
  });

  final GameController controller;

  /// Null for an empty equipment slot, where only the slot itself is described.
  final String? itemId;
  final num quantity;
  final String? enchantmentId;
  final String? slotId;

  @override
  Widget build(BuildContext context) {
    final db = controller.db;
    final id = itemId;
    final item = id == null ? null : controller.indexes.itemsById[id];
    final slot = slotId == null
        ? null
        : db.equipmentSlots.where((row) => row.slotId == slotId).firstOrNull;

    final lines = <String>[
      if (id != null) ...equipmentTooltipStatLines(equipmentForItemId(db, id)),
      ...enchantmentTooltipLines(db, enchantmentId),
      if (id != null && isSpellItem(db, id)) ...spellTooltipLines(db, item, id),
      if (id == null && slotId != null && isSpellSlotId(slotId!))
        'Equip a spell from your bag. Spells are always active.',
    ];

    final description = item?.description;
    final priced = id == null ? null : sellPriceAtLocation(db, controller.save, id);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
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
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
