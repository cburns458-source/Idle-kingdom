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
import 'mailbox_popup.dart';
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
const double _hudHpBarWidth = 76;

/// Settings and mail sit as a pair at the top middle. Smaller than the old 28 chip.
const double _hudHeaderButtonSize = 24;

/// Name stays the heading. Everything else matches body UI (~12) without
/// matching the name, so race / gold / activity stay readable in 56px.
const double _hudNameSize = 14;
const double _hudMetaSize = 11;
const double _hudActivitySize = 12;
const double _hudActivityDetailSize = 11;
const double _hudHpSize = 11;

/// Name, race, totals, gold, HP, and what is running.
class TopHud extends StatelessWidget {
  const TopHud({
    super.key,
    required this.controller,
    required this.multiplayer,
    required this.onOpenWardrobe,
    required this.onOpenMailbox,
    required this.onOpenSettings,
    this.batterySaver = false,
  });

  final GameController controller;
  final MultiplayerController multiplayer;
  final VoidCallback onOpenWardrobe;
  final VoidCallback onOpenMailbox;
  final VoidCallback onOpenSettings;
  final bool batterySaver;

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
    // Structural / social chrome only — meters and the activity timer listen to
    // [controller.progress] so the board texture is not rebuilt every tick.
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[controller, multiplayer]),
      builder: (context, _) => _buildHud(context),
    );
  }

  Widget _buildHud(BuildContext context) {
    final save = controller.save;
    final raceName = raceDisplayName(controller.db, save.raceId) ?? 'Unsworn';
    final characterName = controller.showTitleOnHud
        ? displayNameForSave(save, 'Adventurer')
        : (save.characterName ?? 'Adventurer');
    final tag = multiplayer.showHudGuildTag ? multiplayer.guild?.tag : null;
    final title = tag != null && tag.isNotEmpty ? '[$tag] $characterName' : characterName;
    final totalsLabel = controller.hudShowTotalXp
        ? 'XP ${formatThousands(totalSkillXp(save))}'
        : 'Lv ${formatThousands(totalLevel(save))}';

    return SizedBox(
      height: HudPortrait.size + 2,
      child: DecoratedBox(
        decoration: chromeBarFill(
          context,
          border: Border(
            bottom: BorderSide(
              color: batterySaver ? Palette.gold : Palette.edge,
              width: batterySaver ? 4 : 1,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 8, 2),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const cluster = _hudHeaderButtonSize + 4 + _hudHeaderButtonSize;
              final side = math.max(0.0, (constraints.maxWidth - cluster) / 2);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: side,
                    height: constraints.maxHeight,
                    child: Row(
                      children: [
                        HudPortrait(
                          appearance: save.appearance,
                          raceId: save.raceId,
                          bytes: controller.localPlayerPng,
                          hint:
                              !batterySaver &&
                              !save.hasSeenWardrobeIntro &&
                              save.cosmetics.unlocked.isNotEmpty,
                          onTap: onOpenWardrobe,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Column(
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
                                        fontSize: _hudNameSize,
                                        fontWeight: FontWeight.w400,
                                        height: 1.05,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    raceName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: _hudMetaSize,
                                      fontWeight: FontWeight.w400,
                                      color: Color(0xFFC8D7B6),
                                      height: 1.05,
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
                                        fontSize: _hudMetaSize,
                                        fontWeight: FontWeight.w400,
                                        color: Color(0xFFC8D7B6),
                                        height: 1.05,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  GameImage(uiHudGoldAssetPath(), width: 11, height: 11),
                                  const SizedBox(width: 3),
                                  Expanded(
                                    child: Text(
                                      formatThousands(save.gold),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: _hudMetaSize,
                                        fontWeight: FontWeight.w400,
                                        color: Color(0xFFFFF4D4),
                                        height: 1.05,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  _HudSettingsButton(onTap: onOpenSettings),
                  const SizedBox(width: 4),
                  MailboxHudButton(
                    unread: unreadMailCount(save, controller.session.clock()).toInt(),
                    onTap: onOpenMailbox,
                    size: _hudHeaderButtonSize,
                  ),
                  SizedBox(
                    width: side,
                    height: constraints.maxHeight,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ActivitySlot(controller: controller, status: _status),
                        Align(
                          alignment: Alignment.centerRight,
                          child: _HealthReadout(controller: controller),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The activity line, which is the only part of the HUD's top row on the clock.
///
/// It listens to progress on its own so the name, race, and totals beside it are
/// not rebuilt with every frame of its timer.
class _ActivitySlot extends StatelessWidget {
  const _ActivitySlot({required this.controller, required this.status});

  final GameController controller;
  final _HudStatus? Function() status;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller.progress,
      builder: (context, _) {
        final reading = status();
        if (reading == null) return const SizedBox.shrink();
        return _ActivityReadout(status: reading);
      },
    );
  }
}

/// Hit points and their bar: the other clock-driven corner of the HUD, since
/// natural regain moves them without anything else on the board changing.
class _HealthReadout extends StatelessWidget {
  const _HealthReadout({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller.progress,
      builder: (context, _) {
        final save = controller.save;
        final maxHp = playerMaxHp(controller.db, save);
        final fraction = controller.isRecovering || maxHp <= 0
            ? 0.0
            : (save.currentHp / maxHp).clamp(0, 1).toDouble();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (controller.healPopup case final heal?) ...[
                    Text(
                      heal.amount < 0
                          ? formatThousands(heal.amount)
                          : '+${formatThousands(heal.amount)}',
                      style: TextStyle(
                        fontSize: _hudHpSize,
                        fontWeight: FontWeight.w400,
                        height: 1.05,
                        color: heal.amount < 0 ? const Color(0xFFE8A090) : const Color(0xFF9FE3A8),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    controller.isRecovering
                        ? 'Recovering…'
                        : '${formatThousands(save.currentHp)}/${formatThousands(maxHp)}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: _hudHpSize,
                      fontWeight: FontWeight.w400,
                      height: 1.05,
                      color: controller.isRecovering
                          ? const Color(0xFFE8A090)
                          : const Color(0xFFF0D78C),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 1),
            SizedBox(
              width: _hudHpBarWidth,
              child: Semantics(
                label: 'Hit points',
                value: '${formatThousands(save.currentHp)} / ${formatThousands(maxHp)}',
                child: PillBar(
                  value: fraction,
                  gradient: Meters.hudHp,
                  height: 7,
                  trackColor: Palette.ink,
                  borderColor: const Color(0x599A7B32),
                ),
              ),
            ),
          ],
        );
      },
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
              fontSize: _hudActivitySize,
              fontWeight: FontWeight.w400,
              color: Color(0xFFF4EFD8),
              height: 1.05,
            ),
          ),
          Text(
            '${status.detail} · ${status.timer}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: _hudActivityDetailSize,
              color: Color(0xFFC8D7B6),
              height: 1.05,
            ),
          ),
        ],
      ),
    );
  }
}

/// Settings gear on the HUD header.
class _HudSettingsButton extends StatelessWidget {
  const _HudSettingsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Settings',
      child: Tooltip(
        message: 'Settings',
        child: GestureDetector(
          key: const Key('hud-settings'),
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: _hudHeaderButtonSize,
            height: _hudHeaderButtonSize,
            child: GameImage(
              uiSettingsAssetPath(),
              width: _hudHeaderButtonSize,
              height: _hudHeaderButtonSize,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}

/// The square portrait that opens the wardrobe, sized to sit inside the HUD.
class HudPortrait extends StatelessWidget {
  const HudPortrait({
    super.key,
    required this.appearance,
    this.raceId,
    this.bytes,
    required this.hint,
    required this.onTap,
  });

  static const double size = 56;

  final PlayerAppearance appearance;

  /// The save's people, which picks the race sprite.
  final String? raceId;

  /// A local PNG override, when this device has one.
  final Uint8List? bytes;

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
          child: PixelPlate(
            step: PixelChrome.stepTight,
            strokeWidth: hint ? 2.5 : 2,
            selected: hint,
            shadow: false,
            rivets: false,
            material: PixelPlateMaterial.none,
            fillColor: const Color(0xFF9EC8E8),
            child: ClipPath(
              clipper: PixelSteppedClipper(step: PixelChrome.stepTight),
              child: bytes != null
                  ? PlayerSprite(
                      appearance: appearance,
                      raceId: raceId,
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
                        raceId: raceId,
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
