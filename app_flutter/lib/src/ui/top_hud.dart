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

/// Name, race, totals, gold, HP, and what is running.
///
/// The portrait is painted by [HudPortrait] in the shell stack so the frame can
/// hang below this bar without stretching it.
class TopHud extends StatelessWidget {
  const TopHud({super.key, required this.controller, this.trailing});

  final GameController controller;

  /// Sits on the far right of the bar — currently the chat toggle.
  final Widget? trailing;

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
    final status = _status();

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: const BoxDecoration(
        color: Palette.panel,
        border: Border(bottom: BorderSide(color: Palette.edge)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(width: HudPortrait.size),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                            ),
                          ),
                          Text(
                            '${raceName ?? 'Unsworn'} · '
                            'Lv ${formatThousands(totalLevel(save))}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFC8D7B6),
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (status != null) ...[
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: trailing == null ? 140 : 110),
                        child: _ActivityReadout(status: status),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Image.asset(
                      goldIconPath(),
                      width: 13,
                      height: 13,
                      filterQuality: FilterQuality.none,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      formatThousands(save.gold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFFFF4D4),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      controller.isRecovering
                          ? 'Dead'
                          : '${formatThousands(save.currentHp)}/'
                                '${formatThousands(maxHp)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: controller.isRecovering
                            ? const Color(0xFFE8A090)
                            : const Color(0xFFF0D78C),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
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
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
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
              fontWeight: FontWeight.w700,
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

/// The framed portrait that opens the wardrobe.
///
/// Sized to wrap the head shot, and painted above the location so the ring can
/// hang below the HUD bar.
class HudPortrait extends StatelessWidget {
  const HudPortrait({super.key, required this.appearance, required this.hint, required this.onTap});

  /// The whole control, frame included. Taller than the HUD so the ring drops
  /// over the screen below.
  static const double size = 124;

  /// Inset so the head sits in the ring's hole rather than over its rim.
  static const double _rim = 22;

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
          dimension: size,
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
