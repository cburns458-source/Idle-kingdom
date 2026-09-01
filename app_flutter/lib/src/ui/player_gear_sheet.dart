import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'game_popup.dart';
import 'inventory_view.dart';
import 'item_icon.dart';

/// Opens a read-only paper-doll of another player's equipped gear.
Future<void> openPlayerGear(
  BuildContext context, {
  required GameController controller,
  required String username,
  required List<PublicEquippedSlot>? equipment,
}) {
  return showGamePopup<void>(
    context: context,
    origin: popupOrigin(context),
    builder: (context) =>
        PlayerGearSheet(controller: controller, username: username, equipment: equipment),
  );
}

class PlayerGearSheet extends StatelessWidget {
  const PlayerGearSheet({
    super.key,
    required this.controller,
    required this.username,
    required this.equipment,
  });

  final GameController controller;
  final String username;
  final List<PublicEquippedSlot>? equipment;

  @override
  Widget build(BuildContext context) {
    final hidden = equipment == null;
    final bySlot = <String, PublicEquippedSlot>{
      for (final slot in equipment ?? const <PublicEquippedSlot>[]) slot.slotId: slot,
    };
    return GamePopupCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$username\'s gear',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
                ),
              ),
              GameButton(
                label: 'Close',
                tone: GameButtonTone.secondary,
                compact: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (hidden)
            const MutedText('This player hides their gear.')
          else
            GamePanel(
              framed: true,
              padding: const EdgeInsets.all(8),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    children: [
                      for (final slotId in equipmentGridOrder)
                        _GearSlotTile(
                          slotId: slotId,
                          slot: controller.db.equipmentSlots
                              .where((row) => row.slotId == slotId)
                              .firstOrNull,
                          equipped: bySlot[slotId],
                          item: bySlot[slotId] == null
                              ? null
                              : controller.indexes.itemsById[bySlot[slotId]!.itemId],
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GearSlotTile extends StatelessWidget {
  const _GearSlotTile({
    required this.slotId,
    required this.slot,
    required this.equipped,
    required this.item,
  });

  final String slotId;
  final EquipmentSlotRow? slot;
  final PublicEquippedSlot? equipped;
  final ItemRow? item;

  @override
  Widget build(BuildContext context) {
    if (equipped == null) {
      return PixelPlate(
        step: PixelChrome.stepTight,
        fillColor: Palette.slot,
        material: PixelPlateMaterial.none,
        strokeWidth: 2,
        shadow: false,
        padding: const EdgeInsets.all(3),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SlotGlyph(slotId: slotId, size: 26),
            const SizedBox(height: 2),
            Flexible(
              child: Text(
                slot?.displayName ?? slotId,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 8.5,
                  height: 1.1,
                  color: Palette.muted,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Tooltip(
      message: item?.displayName ?? equipped!.itemId,
      child: PixelPlate(
        step: PixelChrome.stepTight,
        fillColor: Palette.slot,
        material: PixelPlateMaterial.none,
        strokeWidth: 2,
        shadow: false,
        padding: const EdgeInsets.all(4),
        child: Stack(
          children: [
            Center(child: ItemIcon(item: item, size: 36)),
            if (equipped!.enchantmentId != null)
              const Positioned(
                right: 0,
                top: 0,
                child: Text('★', style: TextStyle(fontSize: 11, color: Palette.softGreen)),
              ),
          ],
        ),
      ),
    );
  }
}
