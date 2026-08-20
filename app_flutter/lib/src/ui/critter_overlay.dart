import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../content/asset_paths.dart';
import '../session/game_controller.dart';
import '../theme.dart';
import 'game_image.dart';

/// The critter waiting at this location, tappable on top of the art.
///
/// Renders nothing when nothing is waiting, which is most of the time.
class CritterOverlay extends StatelessWidget {
  const CritterOverlay({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final spawn = activeSpawnAtLocation(controller.save, controller.save.currentLocationId);
    if (spawn == null) return const SizedBox.shrink();
    final critter = getCritter(spawn.critterId);
    if (critter == null) return const SizedBox.shrink();

    return Semantics(
      button: true,
      label: 'Collect ${critter.displayName}',
      // The name is written on the tile too, and a label reading
      // "Collect Fly Fly" is worse than one that does not.
      excludeSemantics: true,
      child: InkWell(
        onTap: controller.collectCritterHere,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Palette.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Palette.gold),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GameImage(critterAssetPath(critter.internalKey), width: 40, height: 40),
              Text(
                critter.displayName,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Offers the tool an activity wants before refusing to start it.
class AutoEquipPrompt extends StatelessWidget {
  const AutoEquipPrompt({super.key, required this.controller, required this.proposal});

  final GameController controller;
  final AutoEquipProposal proposal;

  @override
  Widget build(BuildContext context) {
    final prompt = autoEquipPromptView(proposal);
    return ColoredBox(
      color: const Color(0xCC120C08),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: GamePanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  prompt.title,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(prompt.reason),
                const SizedBox(height: 6),
                MutedText(prompt.question),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      GameButton(
                        label: prompt.cancelLabel,
                        tone: GameButtonTone.secondary,
                        compact: true,
                        onPressed: controller.declineAutoEquip,
                      ),
                      GameButton(
                        label: prompt.confirmLabel,
                        compact: true,
                        onPressed: controller.confirmAutoEquip,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
