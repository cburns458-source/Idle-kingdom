import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../content/asset_paths.dart';
import '../session/game_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'item_icon.dart';
import 'pixel_chrome.dart';

const Color _playerHpFill = Color(0xFF7FAD45);
const Color _enemyHpFill = Color(0xFFD4844A);
const Color _roundFill = Color(0xFF7EB6E8);
const Color _playerHitColor = Color(0xFFFF8A3D);
const Color _critHitColor = Color(0xFFFFD166);
const Color _offhandHitColor = Color(0xFFF0A868);
const Color _enemyHitColor = Color(0xFFFFD0D0);

/// Shared two-column stage for combat, gathering, and production.
///
/// Player art is always on the left. The right side is the enemy, the gathering
/// scene, or the workstation, matching the retired React layout.
class ActionStage extends StatelessWidget {
  const ActionStage({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final save = controller.save;
    if (save.currentActivityId == null) return const SizedBox.shrink();
    if (save.combatEnemyId != null) return _CombatStage(controller: controller);
    if (save.productionRecipeId != null || controller.craftPopup != null) {
      return _ProductionStage(controller: controller);
    }
    return _GatheringStage(controller: controller);
  }
}

class _StageShell extends StatelessWidget {
  const _StageShell({
    required this.semanticsLabel,
    required this.title,
    required this.controller,
    required this.scene,
    required this.footer,
    this.subtitle,
  });

  final String semanticsLabel;
  final String title;
  final String? subtitle;
  final GameController controller;
  final Widget scene;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticsLabel,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      if (subtitle case final line?) MutedText(line),
                    ],
                  ),
                ),
                PixelActionButton(label: 'Stop', stop: true, onPressed: controller.stopActivity),
              ],
            ),
            const SizedBox(height: 6),
            scene,
            const SizedBox(height: 8),
            footer,
          ],
        ),
      ),
    );
  }
}

class _TwoPortraits extends StatelessWidget {
  const _TwoPortraits({
    required this.player,
    required this.scene,
    required this.playerCaption,
    required this.sceneCaption,
  });

  final Widget player;
  final Widget scene;
  final Widget playerCaption;
  final Widget sceneCaption;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [player, const SizedBox(height: 6), playerCaption],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [scene, const SizedBox(height: 6), sceneCaption],
          ),
        ),
      ],
    );
  }
}

class _Portrait extends StatelessWidget {
  const _Portrait({
    required this.assetPath,
    required this.semanticsLabel,
    required this.alignment,
    this.overlay,
    this.placeholder,
  });

  final String? assetPath;
  final String semanticsLabel;
  final Alignment alignment;
  final Widget? overlay;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: placeholder == null,
      label: semanticsLabel,
      child: SizedBox(
        height: 152,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ?placeholder,
            if (placeholder == null)
              Image.asset(
                assetPath!,
                fit: BoxFit.contain,
                alignment: alignment,
                filterQuality: FilterQuality.none,
              ),
            ?overlay,
          ],
        ),
      ),
    );
  }
}

class _CombatStage extends StatelessWidget {
  const _CombatStage({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final save = controller.save;
    final activity = controller.indexes.activitiesById[save.currentActivityId];
    final enemy = getEnemy(controller.db, save.combatEnemyId!);
    final enemyName = enemy?.displayName ?? save.combatEnemyId!;
    final enemyMaxHp = math.max(1, enemy?.maximumHp ?? 1);
    final enemyHp = controller.defeatedFlash ? 0 : (save.combatEnemyHp ?? 0);
    final maxHp = playerMaxHp(controller.db, save);
    final playerHp = save.currentHp;
    final round = controller.lastRound;
    final seq = controller.lastRoundSeq;

    return _StageShell(
      semanticsLabel: 'Combat',
      title: activity?.contextualName ?? save.currentActivityId!,
      controller: controller,
      scene: _TwoPortraits(
        player: _Portrait(
          assetPath: playerAssetPath(save.appearance),
          semanticsLabel: 'Adventurer',
          alignment: Alignment.centerLeft,
          overlay: Stack(
            children: [
              if (round != null && (round.enemyHit ?? 0) > 0 && !controller.defeatedFlash)
                _DamageFloater(
                  key: ValueKey('enemy-hit-$seq'),
                  text: '${round.enemyHit!.round()}',
                  color: _enemyHitColor,
                  alignment: const Alignment(-0.15, 0.1),
                  offset: _floaterOffset(seq, 1),
                ),
              if (controller.isRecovering)
                Center(
                  child: Text(
                    'Recovering… ${_pauseSeconds(controller.deathPauseRemainingMs)}s',
                    style: pixelCaption(color: Palette.danger, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
        scene: _Portrait(
          assetPath: controller.defeatedFlash ? null : enemyAssetPath(save.combatEnemyId!),
          semanticsLabel: enemyName,
          alignment: Alignment.centerRight,
          placeholder: controller.defeatedFlash
              ? Center(
                  child: Text('defeated', style: pixelCaption(color: Palette.danger, fontSize: 16)),
                )
              : null,
          overlay: controller.defeatedFlash
              ? null
              : Stack(
                  children: [
                    if (round != null && round.playerHit > 0)
                      _DamageFloater(
                        key: ValueKey('player-hit-$seq'),
                        text: round.playerCrit
                            ? 'CRIT ${round.playerHit.round()}'
                            : '${round.playerHit.round()}',
                        color: round.playerCrit ? _critHitColor : _playerHitColor,
                        alignment: const Alignment(0, -0.55),
                        offset: _floaterOffset(seq, 2),
                      ),
                    if (round != null && (round.offhandHit ?? 0) > 0)
                      _DamageFloater(
                        key: ValueKey('offhand-hit-$seq'),
                        text: '${round.offhandHit!.round()}',
                        color: _offhandHitColor,
                        alignment: const Alignment(0, -0.1),
                        offset: _floaterOffset(seq, 3),
                        fontSize: 16,
                      ),
                  ],
                ),
        ),
        playerCaption: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 14),
            Semantics(
              label: 'Player health',
              value: '${playerHp.round()} / ${maxHp.round()}',
              child: PixelMeterBar(
                value: (playerHp / maxHp).clamp(0, 1).toDouble(),
                color: _playerHpFill,
              ),
            ),
          ],
        ),
        sceneCaption: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              enemyName,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Semantics(
              label: '$enemyName health',
              value: '${enemyHp.round()} / ${enemyMaxHp.round()}',
              child: PixelMeterBar(
                value: (enemyHp / enemyMaxHp).clamp(0, 1).toDouble(),
                color: _enemyHpFill,
              ),
            ),
          ],
        ),
      ),
      footer: controller.isRecovering || controller.defeatedFlash
          ? const SizedBox.shrink()
          : Semantics(
              label: 'Round progress',
              child: PixelMeterBar(
                value: controller.combatRoundProgress,
                color: _roundFill,
                height: 8,
              ),
            ),
    );
  }
}

class _GatheringStage extends StatelessWidget {
  const _GatheringStage({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final save = controller.save;
    final activity = controller.indexes.activitiesById[save.currentActivityId];
    final action = save.currentActionId == null
        ? null
        : controller.indexes.actionsById[save.currentActionId!];
    final actionName = action?.displayName ?? 'Preparing…';
    final durationMs = save.actionDurationMs ?? 0;
    final progress = controller.actionProgress;
    final slow = action != null && isBelowProficiency(save, action);

    return _StageShell(
      semanticsLabel: 'Gathering',
      title: activity?.contextualName ?? save.currentActivityId!,
      controller: controller,
      scene: _TwoPortraits(
        player: _Portrait(
          assetPath: playerAssetPath(save.appearance),
          semanticsLabel: 'Adventurer',
          alignment: Alignment.centerLeft,
        ),
        scene: _Portrait(
          assetPath: action == null ? null : actionAssetPath(action.actionId),
          semanticsLabel: actionName,
          alignment: Alignment.centerRight,
          placeholder: action == null
              ? Center(child: Text('…', style: pixelCaption(fontSize: 22)))
              : null,
        ),
        playerCaption: const SizedBox(height: 14),
        sceneCaption: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              actionName,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            if (slow)
              Text(
                'this is tough work',
                style: pixelCaption(color: const Color(0xFFC9B896), fontSize: 11),
              ),
          ],
        ),
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: 'Action progress',
            child: PixelMeterBar(value: progress, color: Palette.softGreen),
          ),
          const SizedBox(height: 4),
          MutedText('${formatDurationMs(durationMs * progress)} / ${formatDurationMs(durationMs)}'),
        ],
      ),
    );
  }
}

class _ProductionStage extends StatelessWidget {
  const _ProductionStage({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final save = controller.save;
    final activity = controller.indexes.activitiesById[save.currentActivityId];
    final recipeId = save.productionRecipeId;
    final recipe = recipeId == null ? null : getRecipe(controller.db, recipeId);
    final popup = controller.craftPopup;
    final popupItem = popup == null ? null : controller.indexes.itemsById[popup.itemId];
    final stationId = recipe?.facilityId;

    return _StageShell(
      semanticsLabel: 'Production',
      title: activity?.contextualName ?? save.currentActivityId!,
      subtitle: recipeId == null ? null : _queueLine(controller, recipeId),
      controller: controller,
      scene: _TwoPortraits(
        player: _Portrait(
          assetPath: playerAssetPath(save.appearance),
          semanticsLabel: 'Adventurer',
          alignment: Alignment.centerLeft,
        ),
        scene: _Portrait(
          assetPath: workstationAssetPath(stationId),
          semanticsLabel: recipe?.displayName ?? popup?.displayName ?? 'Workstation',
          alignment: Alignment.centerRight,
          overlay: popup == null
              ? null
              : Align(
                  alignment: const Alignment(0, -0.55),
                  child: Semantics(
                    liveRegion: true,
                    label: popup.displayName,
                    child: ExcludeSemantics(
                      child: TweenAnimationBuilder<double>(
                        key: ValueKey('craft-pop-${popup.seq}'),
                        tween: Tween<double>(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 420),
                        curve: Curves.easeOut,
                        builder: (context, t, child) {
                          return Opacity(
                            opacity: t.clamp(0, 1),
                            child: Transform.translate(
                              offset: Offset(0, (1 - t) * 10),
                              child: Transform.scale(scale: 0.85 + 0.15 * t, child: child),
                            ),
                          );
                        },
                        child: ItemIcon(item: popupItem, size: 38),
                      ),
                    ),
                  ),
                ),
        ),
        playerCaption: const SizedBox(height: 14),
        sceneCaption: const SizedBox(height: 14),
      ),
      footer: Semantics(
        label: 'Action progress',
        child: PixelMeterBar(value: controller.actionProgress, color: Palette.softGreen),
      ),
    );
  }
}

class _DamageFloater extends StatelessWidget {
  const _DamageFloater({
    super.key,
    required this.text,
    required this.color,
    required this.alignment,
    required this.offset,
    this.fontSize = 20,
  });

  final String text;
  final Color color;
  final Alignment alignment;
  final Offset offset;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Transform.translate(
        offset: offset,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOut,
          builder: (context, t, child) {
            return Opacity(
              opacity: t,
              child: Transform.translate(offset: Offset(0, (1 - t) * 8), child: child),
            );
          },
          child: Text(
            text,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: color,
              shadows: const [
                Shadow(color: Color(0xD9000000), blurRadius: 2),
                Shadow(offset: Offset(0, 2), color: Color(0x8C000000), blurRadius: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Copper Bar · 3/10 · 7m 30s left" for a running craft queue.
String _queueLine(GameController controller, String recipeId) {
  final save = controller.save;
  final recipe = getRecipe(controller.db, recipeId);
  final total = save.productionQuantityTotal ?? 0;
  final remaining = save.productionQuantityRemaining ?? 0;
  final craftMs = save.actionDurationMs ?? 0;
  final leftOfCurrent = craftMs * (1 - controller.actionProgress);
  final queuedAfter = remaining > 0 ? remaining - 1 : 0;
  final name = recipe?.displayName ?? recipeId;
  return '$name · ${total - remaining}/$total · '
      '${formatDurationMs(leftOfCurrent + queuedAfter * craftMs)} left';
}

Offset _floaterOffset(int seq, int salt) {
  final mixed = seq * 31 + salt * 17;
  return Offset(((mixed % 49) - 24).toDouble(), (((mixed ~/ 7) % 37) - 18).toDouble());
}

int _pauseSeconds(num remainingMs) {
  if (remainingMs <= 0) return 0;
  return (remainingMs / 1000).ceil();
}
