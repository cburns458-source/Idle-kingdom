import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../content/asset_paths.dart';
import '../session/game_controller.dart';
import '../theme.dart';
import 'format.dart';

/// What the player is busy with, read out in the corner of the HUD.
class _HudStatus {
  const _HudStatus({required this.title, required this.detail, required this.timer});

  final String title;

  /// The action being repeated, the enemy being fought, or the craft count.
  final String detail;
  final String timer;
}

/// Name, race, totals, gold, HP, what is running, and the last few rewards.
class TopHud extends StatelessWidget {
  const TopHud({super.key, required this.controller, required this.onOpenWardrobe});

  final GameController controller;

  /// Tapping the portrait opens the wardrobe.
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
    final raceName = raceDisplayName(controller.db, save.raceId);
    // Something to wear and no wardrobe visit yet: worth pointing at.
    final hint = !save.hasSeenWardrobeIntro && save.cosmetics.unlocked.isNotEmpty;
    final status = _status();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
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
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                save.characterName ?? 'Adventurer',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                              ),
                              MutedText(raceName ?? 'Unsworn'),
                              Text(
                                'Total level: ${formatThousands(totalLevel(save))}',
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFC8D7B6),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Image.asset(
                                    goldIconPath(),
                                    width: 14,
                                    height: 14,
                                    filterQuality: FilterQuality.none,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      formatThousands(save.gold),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFFFFF4D4),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (status != null) ...[
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 152),
                            child: _ActivityReadout(status: status),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Spacer(),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                controller.isRecovering
                                    ? 'Dead'
                                    : '${formatThousands(save.currentHp)}/'
                                          '${formatThousands(maxHp)}',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: controller.isRecovering
                                      ? const Color(0xFFE8A090)
                                      : const Color(0xFFF0D78C),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Semantics(
                                label: 'Hit points',
                                value:
                                    '${formatThousands(save.currentHp)} / '
                                    '${formatThousands(maxHp)}',
                                child: PillBar(
                                  value: hpFraction,
                                  gradient: Meters.hudHp,
                                  height: 9,
                                  trackColor: const Color(0x59120C08),
                                  borderColor: const Color(0x59D4AF37),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
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
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFFF4EFD8),
              height: 1.15,
            ),
          ),
          Text(
            status.detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFFD8D0B8),
              height: 1.15,
            ),
          ),
          Text(
            status.timer,
            maxLines: 1,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11.5, color: Color(0xFFC8D7B6), height: 1.15),
          ),
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
  static const double _size = 96;

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
