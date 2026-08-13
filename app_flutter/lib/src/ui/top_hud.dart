import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../content/asset_paths.dart';
import '../session/game_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'item_icon.dart';
import 'reward_strip.dart';

/// Name, race, totals, gold, HP, and the reward lines from the last few actions.
class TopHud extends StatelessWidget {
  const TopHud({super.key, required this.controller, required this.onOpenWardrobe});

  final GameController controller;

  /// Tapping the portrait opens the wardrobe, as it does in the React client.
  final VoidCallback onOpenWardrobe;

  @override
  Widget build(BuildContext context) {
    final save = controller.save;
    final maxHp = playerMaxHp(controller.db, save);
    final hpFraction = maxHp <= 0 ? 0.0 : (save.currentHp / maxHp).clamp(0, 1).toDouble();
    final raceName = raceDisplayName(controller.db, save.raceId);
    // Something to wear and no wardrobe visit yet: worth pointing at.
    final hint = !save.hasSeenWardrobeIntro && save.cosmetics.unlocked.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Palette.edge)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AvatarButton(appearance: save.appearance, hint: hint, onTap: onOpenWardrobe),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      save.characterName ?? 'Adventurer',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    MutedText(raceName ?? 'Unsworn'),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  MutedText('Total level ${totalLevel(save)}'),
                  GoldAmount(
                    amount: save.gold,
                    size: 16,
                    style: const TextStyle(color: Palette.gold, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: MeterBar(value: hpFraction, color: Palette.softGreen, height: 10),
              ),
              const SizedBox(width: 8),
              Text(
                controller.isRecovering
                    ? 'Dead'
                    : '${formatThousands(save.currentHp)}/${formatThousands(maxHp)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: controller.isRecovering ? Palette.danger : Palette.parchmentText,
                ),
              ),
            ],
          ),
          if (controller.recentRewards.isNotEmpty) ...[
            const SizedBox(height: 6),
            RewardStrip(controller: controller),
          ],
        ],
      ),
    );
  }
}

/// The framed portrait that opens the wardrobe.
///
/// The ring is the shared pixel frame rather than a painted border, and the
/// sprite is zoomed on its head, so the portrait reads as a face at HUD size.
class _AvatarButton extends StatelessWidget {
  const _AvatarButton({required this.appearance, required this.hint, required this.onTap});

  /// The whole control, frame included.
  static const double _size = 56;

  /// How far inside the frame's rim the portrait sits.
  static const double _rim = _size * 0.08;

  /// Enough of the sprite's height to fill the circle with its head.
  static const double _headZoom = 1.7;

  final PlayerAppearance appearance;

  /// Rings the frame in gold until the wardrobe has been opened once.
  final bool hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open wardrobe',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox.square(
          dimension: _size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.all(_rim),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF9EC8E8),
                    boxShadow: hint
                        ? const [BoxShadow(color: Palette.gold, blurRadius: 8, spreadRadius: 1)]
                        : null,
                  ),
                  child: ClipOval(
                    child: Transform.scale(
                      scale: _headZoom,
                      alignment: Alignment.topCenter,
                      child: Image.asset(
                        playerAssetPath(appearance),
                        filterQuality: FilterQuality.none,
                        alignment: Alignment.topCenter,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: Image.asset(avatarFrameAssetPath(), filterQuality: FilterQuality.none),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
