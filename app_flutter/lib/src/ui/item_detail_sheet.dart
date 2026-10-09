import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
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

  /// True for equippable bag stacks and for worn gear. Empty slots stay off.
  final bool allowCompare;

  @override
  State<ItemDetailSheet> createState() => _ItemDetailSheetState();
}

class _ItemDetailSheetState extends State<ItemDetailSheet> {
  bool _comparing = false;
  int _candidateIndex = 0;

  /// Worn gear compares against bag stacks; bag gear against what is worn.
  bool get _wornMode => widget.slotId != null && widget.onEquip == null;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final db = controller.db;
    final save = controller.save;
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
    final priced = id == null ? null : sellPriceAtLocation(db, save, id);
    final canCompare =
        widget.allowCompare &&
        id != null &&
        equipmentForItemId(db, id) != null &&
        !(widget.slotId != null && (isFoodSlot(widget.slotId!) || isPotionSlot(widget.slotId!)));

    final wornCandidates = canCompare && _wornMode
        ? compareCandidatesForSlot(db, save, widget.slotId!)
        : const <({String itemId, String? enchantmentId})>[];
    final candidateIndex = wornCandidates.isEmpty
        ? 0
        : _candidateIndex.clamp(0, wornCandidates.length - 1);

    EquipmentCompareResult? compare;
    if (canCompare && _comparing) {
      if (!_wornMode) {
        compare = compareEquipmentCandidate(
          db,
          save,
          itemId: id,
          enchantmentId: widget.enchantmentId,
        );
      } else if (wornCandidates.isNotEmpty) {
        final pick = wornCandidates[candidateIndex];
        compare = compareEquipmentCandidate(
          db,
          save,
          itemId: pick.itemId,
          enchantmentId: pick.enchantmentId,
          targetSlotId: widget.slotId,
        );
      }
    }

    final actions = <Widget>[
      if (widget.onEat != null)
        _ActionButton(
          label: 'Eat',
          onPressed: widget.eatEnabled
              ? () {
                  Navigator.of(context).pop();
                  widget.onEat!();
                }
              : null,
        ),
      if (widget.onEquip != null)
        _ActionButton(
          label: 'Equip',
          onPressed: () {
            Navigator.of(context).pop();
            widget.onEquip!();
          },
        ),
      if (canCompare)
        _ActionButton(
          label: _comparing ? 'Hide' : 'Compare',
          tone: GameButtonTone.secondary,
          onPressed: () => setState(() => _comparing = !_comparing),
        ),
      if (widget.onOpenCodex != null)
        _ActionButton(
          label: 'Codex',
          tone: GameButtonTone.secondary,
          onPressed: () {
            Navigator.of(context).pop();
            widget.onOpenCodex!();
          },
        ),
    ];

    return GamePopupCard(
      child: GamePanel(
        framed: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                if (widget.onToggleFavorite != null) ...[
                  const SizedBox(width: 6),
                  _FavoriteHeartButton(
                    favorite: widget.favorite,
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onToggleFavorite!();
                    },
                  ),
                ],
                const SizedBox(width: 6),
                GameIconButton(
                  icon: Icons.close,
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
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
            if (canCompare && _comparing) ...[
              const SizedBox(height: 10),
              if (_wornMode && wornCandidates.isEmpty)
                const MutedText('No other gear for this slot in your bag.')
              else ...[
                if (_wornMode && wornCandidates.length > 1) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var i = 0; i < wornCandidates.length; i++)
                        GameButton(
                          label:
                              controller.indexes.itemsById[wornCandidates[i].itemId]?.displayName ??
                              wornCandidates[i].itemId,
                          compact: true,
                          tone: i == candidateIndex
                              ? GameButtonTone.primary
                              : GameButtonTone.secondary,
                          onPressed: () => setState(() => _candidateIndex = i),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                if (compare != null)
                  _EquipmentComparePanel(
                    result: compare,
                    controller: controller,
                    candidateHeading: _wornMode ? 'From bag' : 'This item',
                  ),
              ],
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(child: actions[i]),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onPressed,
    this.tone = GameButtonTone.primary,
  });

  final String label;
  final VoidCallback? onPressed;
  final GameButtonTone tone;

  @override
  Widget build(BuildContext context) {
    return GameButton(label: label, compact: true, tone: tone, onPressed: onPressed);
  }
}

class _FavoriteHeartButton extends StatelessWidget {
  const _FavoriteHeartButton({required this.favorite, required this.onPressed});

  final bool favorite;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = favorite ? 'Unfavorite' : 'Favorite';
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: PixelInkPlate(
          onTap: onPressed,
          step: PixelChrome.stepTight,
          fillColor: UiChrome.of(context).iconButtonFill,
          material: PixelPlateMaterial.grain,
          strokeWidth: 1.5,
          shadow: false,
          child: SizedBox.square(
            dimension: 32,
            child: Center(
              child: Text(
                favorite ? '❤️' : '🤍',
                key: const Key('item-favorite-heart'),
                style: const TextStyle(fontSize: GameFont.m, height: 1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EquipmentComparePanel extends StatelessWidget {
  const _EquipmentComparePanel({
    required this.result,
    required this.controller,
    required this.candidateHeading,
  });

  final EquipmentCompareResult result;
  final GameController controller;
  final String candidateHeading;

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
          _CompareItemBlock(
            heading: 'Equipped',
            item: equippedItem,
            name: result.slotEmpty ? 'Empty' : (result.equippedName ?? 'Empty'),
            rows: [for (final row in result.stats) (row.label, row.equippedText, row.equippedKind)],
          ),
          const SizedBox(height: 10),
          _CompareItemBlock(
            heading: candidateHeading,
            item: candidateItem,
            name: result.candidateName,
            rows: [
              for (final row in result.stats) (row.label, row.candidateText, row.candidateKind),
            ],
          ),
          if (result.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final note in result.notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  note,
                  style: const TextStyle(fontSize: GameFont.s, color: Palette.gold),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CompareItemBlock extends StatelessWidget {
  const _CompareItemBlock({
    required this.heading,
    required this.item,
    required this.name,
    required this.rows,
  });

  final String heading;
  final ItemRow? item;
  final String name;
  final List<(String, String, EquipCompareDeltaKind)> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MutedText(heading),
        const SizedBox(height: 2),
        Row(
          children: [
            ItemIcon(item: item, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Text(name, style: const TextStyle(fontSize: GameFont.m)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final (label, value, kind) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              '$label: $value',
              style: TextStyle(fontSize: GameFont.s, color: _lineColor(kind)),
            ),
          ),
      ],
    );
  }
}

Color _lineColor(EquipCompareDeltaKind kind) {
  return switch (kind) {
    EquipCompareDeltaKind.improved => Palette.softGreen,
    EquipCompareDeltaKind.reduced => Palette.danger,
    EquipCompareDeltaKind.unchanged => Palette.muted,
    EquipCompareDeltaKind.special => Palette.gold,
  };
}
