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
class ItemDetailSheet extends StatefulWidget {
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
    this.onOpenCodex,
    this.onToggleFavorite,
    this.favorite = false,
    this.allowCompare = false,
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

  /// Opens this item in the Codex encyclopedia.
  final VoidCallback? onOpenCodex;

  /// Pins or unpins this bag or worn stack. Omitted for empty slots.
  final VoidCallback? onToggleFavorite;

  /// Whether this bag or worn stack is already pinned.
  final bool favorite;

  /// True for bag stacks that can be equipped. Worn gear and empty slots stay off.
  final bool allowCompare;

  @override
  State<ItemDetailSheet> createState() => _ItemDetailSheetState();
}

class _ItemDetailSheetState extends State<ItemDetailSheet> {
  bool _comparing = false;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final db = controller.db;
    final id = widget.itemId;
    final item = id == null ? null : controller.indexes.itemsById[id];
    final slot = widget.slotId == null
        ? null
        : db.equipmentSlots.where((row) => row.slotId == widget.slotId).firstOrNull;

    final lines = <String>[
      if (id != null) ...equipmentTooltipStatLines(equipmentForItemId(db, id), db),
      ...enchantmentTooltipLines(db, widget.enchantmentId),
      if (id != null && isSpellItem(db, id)) ...spellTooltipLines(db, item, id),
      if (id == null && widget.slotId != null && isSpellSlotId(widget.slotId!))
        'Equip a spell from your bag. Spells are always active.',
    ];

    final description = id != null && isBotanySeedItem(db, id) ? null : item?.description;
    final priced = id == null ? null : sellPriceAtLocation(db, controller.save, id);
    final compareItemId = id;
    final canCompare =
        widget.allowCompare &&
        compareItemId != null &&
        equipmentForItemId(db, compareItemId) != null;
    final compare = canCompare && _comparing
        ? compareEquipmentCandidate(
            db,
            controller.save,
            itemId: compareItemId,
            enchantmentId: widget.enchantmentId,
          )
        : null;

    return GamePopupCard(
      child: GamePanel(
        framed: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (id == null && widget.slotId != null)
                  SlotGlyph(slotId: widget.slotId!, size: 38)
                else
                  ItemIcon(item: item, size: 38),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item?.displayName ?? slot?.displayName ?? id ?? 'Empty slot',
                        style: const TextStyle(fontSize: GameFont.l, fontWeight: FontWeight.w400),
                      ),
                      if (widget.quantity > 1) MutedText('×${formatThousands(widget.quantity)}'),
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
                  child: Text(line, style: const TextStyle(fontSize: GameFont.m)),
                ),
            ],
            if (priced != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: MutedText(priced.shopId == null ? 'Field value each' : 'Shop pays each'),
                  ),
                  const SizedBox(width: 6),
                  GoldAmount(
                    amount: priced.unitPrice,
                    style: const TextStyle(fontSize: GameFont.m),
                  ),
                ],
              ),
            ],
            if (compare != null) ...[
              const SizedBox(height: 10),
              _EquipmentComparePanel(result: compare, controller: controller),
            ],
            const SizedBox(height: 10),
            if (widget.onToggleFavorite != null) ...[
              GameButton(
                label: widget.favorite ? 'Unfavorite' : 'Favorite',
                compact: true,
                tone: GameButtonTone.secondary,
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onToggleFavorite!();
                },
              ),
              const SizedBox(height: 6),
            ],
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (widget.onEat != null)
                  _ActionChip(
                    label: 'Eat',
                    onPressed: widget.eatEnabled
                        ? () {
                            Navigator.of(context).pop();
                            widget.onEat!();
                          }
                        : null,
                  ),
                if (widget.onEquip != null)
                  _ActionChip(
                    label: 'Equip',
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onEquip!();
                    },
                  ),
                if (canCompare)
                  _ActionChip(
                    label: _comparing ? 'Hide compare' : 'Compare',
                    tone: GameButtonTone.secondary,
                    onPressed: () => setState(() => _comparing = !_comparing),
                  ),
                if (widget.onOpenCodex != null)
                  _ActionChip(
                    label: 'Codex',
                    tone: GameButtonTone.secondary,
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onOpenCodex!();
                    },
                  ),
                _ActionChip(
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

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.onPressed,
    this.tone = GameButtonTone.primary,
  });

  final String label;
  final VoidCallback? onPressed;
  final GameButtonTone tone;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      child: GameButton(label: label, compact: true, tone: tone, onPressed: onPressed),
    );
  }
}

class _EquipmentComparePanel extends StatelessWidget {
  const _EquipmentComparePanel({required this.result, required this.controller});

  final EquipmentCompareResult result;
  final GameController controller;

  @override
  Widget build(BuildContext context) {
    if (!result.ok) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: Palette.edge),
          color: const Color(0x332A1C12),
        ),
        child: Text(
          result.reason ?? 'Cannot compare that item.',
          style: const TextStyle(fontSize: GameFont.m, color: Palette.warning),
        ),
      );
    }

    final equippedItem = result.equippedItemId == null
        ? null
        : controller.indexes.itemsById[result.equippedItemId!];
    final candidateItem = controller.indexes.itemsById[result.candidateItemId];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Palette.edge),
        color: const Color(0x332A1C12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Compare',
            style: TextStyle(
              fontSize: GameFont.m,
              fontWeight: FontWeight.w400,
              color: Palette.gold,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              ItemIcon(item: candidateItem, size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(result.candidateName, style: const TextStyle(fontSize: GameFont.m)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          MutedText(
            result.slotEmpty
                ? 'Currently equipped: none'
                : 'Currently equipped: ${result.equippedName}',
          ),
          if (!result.slotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                ItemIcon(item: equippedItem, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.equippedName ?? 'Empty',
                    style: const TextStyle(fontSize: GameFont.m),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          for (final line in result.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                _lineText(line),
                style: TextStyle(fontSize: GameFont.s, color: _lineColor(line.kind)),
              ),
            ),
        ],
      ),
    );
  }

  String _lineText(EquipCompareLine line) {
    if (line.before != null && line.after != null) {
      return '${line.label}: ${line.before} → ${line.after} (${line.detail})';
    }
    return '${line.label}: ${line.detail}';
  }

  Color _lineColor(EquipCompareDeltaKind kind) {
    return switch (kind) {
      EquipCompareDeltaKind.improved => Palette.softGreen,
      EquipCompareDeltaKind.reduced => Palette.danger,
      EquipCompareDeltaKind.unchanged => Palette.muted,
      EquipCompareDeltaKind.special => Palette.gold,
    };
  }
}
