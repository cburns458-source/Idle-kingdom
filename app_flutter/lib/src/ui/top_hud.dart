import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../content/asset_paths.dart';
import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'game_image.dart';
import 'player_sprite.dart';

/// What the player is busy with, read out in the corner of the HUD.
class _HudStatus {
  const _HudStatus({required this.title, required this.detail, required this.timer});

  final String title;

  /// The action being repeated, the enemy being fought, or the craft count.
  final String detail;
  final String timer;
}

/// How wide the HUD hit-point track is. Short, and parked on the HUD's bottom edge.
const double _hudHpBarWidth = 88;

/// Name, race, totals, gold, HP, and what is running.
class TopHud extends StatelessWidget {
  const TopHud({
    super.key,
    required this.controller,
    required this.multiplayer,
    required this.onOpenWardrobe,
  });

  final GameController controller;
  final MultiplayerController multiplayer;
  final VoidCallback onOpenWardrobe;

  /// A running craft queue reads as the item and how much of the order is left;
  /// anything else reads as the activity, its action, and how long it has run.
  _HudStatus? _status() {
    final save = controller.save;
    final recipeId = save.productionRecipeId;
    final remaining = save.productionQuantityRemaining ?? 0;
    if (recipeId != null && remaining > 0) {
      final total = save.productionQuantityTotal ?? 0;
      final craftMs = save.actionDurationMs ?? 0;
      final left = craftMs * (1 - controller.actionProgress) + (remaining - 1) * craftMs;
      return _HudStatus(
        title: getRecipe(controller.db, recipeId)?.displayName ?? recipeId,
        detail: '${total - remaining}/$total',
        timer: formatDurationMs(left),
      );
    }

    final activityId = save.currentActivityId;
    if (activityId == null) return null;
    final startedMs = jsDateParse(save.activityStartedAt);
    final elapsedMs = startedMs.isFinite ? math.max(0, controller.session.clock() - startedMs) : 0;
    final action = save.currentActionId == null
        ? null
        : controller.indexes.actionsById[save.currentActionId!];
    final enemy = save.combatEnemyId == null ? null : getEnemy(controller.db, save.combatEnemyId!);
    return _HudStatus(
      title: controller.indexes.activitiesById[activityId]?.contextualName ?? activityId,
      detail: enemy?.displayName ?? action?.displayName ?? '…',
      timer: formatDurationMs(elapsedMs),
    );
  }

  @override
  Widget build(BuildContext context) {
    final save = controller.save;
    final maxHp = playerMaxHp(controller.db, save);
    final hpFraction = controller.isRecovering || maxHp <= 0
        ? 0.0
        : (save.currentHp / maxHp).clamp(0, 1).toDouble();
    final raceName = raceDisplayName(controller.db, save.raceId) ?? 'Unsworn';
    final status = _status();
    final characterName = controller.showTitleOnHud
        ? displayNameForSave(save, 'Adventurer')
        : (save.characterName ?? 'Adventurer');
    final tag = multiplayer.showHudGuildTag ? multiplayer.guild?.tag : null;
    final title = tag != null && tag.isNotEmpty ? '[$tag] $characterName' : characterName;
    final totalsLabel = controller.hudShowTotalXp
        ? 'XP ${formatThousands(totalSkillXp(save))}'
        : 'Lv ${formatThousands(totalLevel(save))}';

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: panelFill(
        border: const Border(bottom: BorderSide(color: Palette.edge)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          HudPortrait(
            appearance: save.appearance,
            bytes: controller.localPlayerPng,
            hint: !save.hasSeenWardrobeIntro && save.cosmetics.unlocked.isNotEmpty,
            onTap: onOpenWardrobe,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: HudPortrait.size),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Shrinks rather than clips, so a title is never cut in half.
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                title,
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
                                  height: 1.15,
                                ),
                              ),
                            ),
                            Text(
                              raceName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w400,
                                color: Color(0xFFC8D7B6),
                                height: 1.2,
                              ),
                            ),
                            GestureDetector(
                              onTap: controller.toggleHudShowTotalXp,
                              behavior: HitTestBehavior.opaque,
                              child: Text(
                                totalsLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w400,
                                  color: Color(0xFFC8D7B6),
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (status != null) ...[
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 140),
                          child: _ActivityReadout(status: status),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      GameImage(goldIconPath(), width: 13, height: 13),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          formatThousands(save.gold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFFFFF4D4),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            controller.isRecovering
                                ? 'Recovering…'
                                : '${formatThousands(save.currentHp)}/'
                                      '${formatThousands(maxHp)}',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                              color: controller.isRecovering
                                  ? const Color(0xFFE8A090)
                                  : const Color(0xFFF0D78C),
                            ),
                          ),
                          const SizedBox(height: 2),
                          SizedBox(
                            width: _hudHpBarWidth,
                            child: Semantics(
                              label: 'Hit points',
                              value:
                                  '${formatThousands(save.currentHp)} / '
                                  '${formatThousands(maxHp)}',
                              child: PillBar(
                                value: hpFraction,
                                gradient: Meters.hudHp,
                                height: 8,
                                trackColor: Palette.ink,
                                borderColor: const Color(0x59D4AF37),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityReadout extends StatelessWidget {
  const _ActivityReadout({required this.status});

  final _HudStatus status;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            status.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: Color(0xFFF4EFD8),
              height: 1.1,
            ),
          ),
          Text(
            '${status.detail} · ${status.timer}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 10.5, color: Color(0xFFC8D7B6), height: 1.1),
          ),
        ],
      ),
    );
  }
}

/// The square portrait that opens the wardrobe, sized to sit inside the HUD.
class HudPortrait extends StatelessWidget {
  const HudPortrait({
    super.key,
    required this.appearance,
    this.bytes,
    required this.hint,
    required this.onTap,
  });

  static const double size = 68;

  static const double _cornerRadius = 6;

  final PlayerAppearance appearance;

  /// A local PNG override, when this device has one.
  final Uint8List? bytes;

  /// Rings the frame in gold until the wardrobe has been opened once.
  final bool hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(_cornerRadius);
    return Semantics(
      button: true,
      label: 'Open wardrobe',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox.square(
          dimension: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              color: const Color(0xFF9EC8E8),
              boxShadow: hint
                  ? const [BoxShadow(color: Palette.gold, blurRadius: 8, spreadRadius: 1)]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: bytes != null
                  ? PlayerSprite(
                      appearance: appearance,
                      bytes: bytes,
                      filterQuality: FilterQuality.none,
                      alignment: Alignment.center,
                      fit: BoxFit.cover,
                    )
                  : Transform.scale(
                      scale: playerPortraitHeadZoom,
                      alignment: Alignment.topCenter,
                      child: PlayerSprite(
                        appearance: appearance,
                        bytes: bytes,
                        filterQuality: FilterQuality.none,
                        alignment: Alignment.topCenter,
                        fit: BoxFit.cover,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
