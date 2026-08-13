import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../content/asset_paths.dart';
import '../session/game_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'item_icon.dart';

/// How tall a fighter, a gathering scene, or a workstation is drawn.
const double _portraitHeight = 152;

/// How wide either half of the stage can get, so the two sprites stay shoulder
/// to shoulder in the middle of a wide window instead of drifting apart.
const double _stageMaxWidth = 460;

const Color _playerHitColor = Color(0xFFFF8A3D);
const Color _critHitColor = Color(0xFFFFD166);
const Color _offhandHitColor = Color(0xFFF0A868);
const Color _enemyHitColor = Color(0xFFFFD0D0);
const Color _sceneNameColor = Color(0xFFF4EFD8);

/// Shared two-column stage for combat, gathering, and production.
///
/// Player art is always on the left. The right side is the enemy, the gathering
/// scene, or the workstation. Stopping lives on the activity row underneath, so
/// the stage is only ever art, names, and bars.
class ActionStage extends StatelessWidget {
  const ActionStage({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final save = controller.save;
    if (save.currentActivityId == null) return const SizedBox.shrink();
    // Defeat clears the enemy and the action, so the pause gets its own skin
    // rather than falling through to a gathering scene with nothing in it.
    if (controller.isRecovering) return _RecoveringStage(controller: controller);
    if (save.combatEnemyId != null) return _CombatStage(controller: controller);
    if (save.productionRecipeId != null || controller.craftPopup != null) {
      return _ProductionStage(controller: controller);
    }
    return _GatheringStage(controller: controller);
  }
}

class _StageShell extends StatelessWidget {
  const _StageShell({required this.semanticsLabel, required this.scene, required this.footer});

  final String semanticsLabel;
  final Widget scene;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticsLabel,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 6),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _stageMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [scene, const SizedBox(height: 7), footer],
            ),
          ),
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
            children: [player, const SizedBox(height: 5), playerCaption],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [scene, const SizedBox(height: 5), sceneCaption],
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
    this.bytes,
    this.overlay,
    this.placeholder,
  });

  final String? assetPath;
  final Uint8List? bytes;
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
        height: _portraitHeight,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ?placeholder,
            if (placeholder == null)
              bytes != null
                  ? Image.memory(
                      bytes!,
                      fit: BoxFit.contain,
                      alignment: alignment,
                      filterQuality: FilterQuality.none,
                      gaplessPlayback: true,
                    )
                  : Image.asset(
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

/// The name over a bar: the enemy, or whatever is being worked on.
class _SceneName extends StatelessWidget {
  const _SceneName(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.right,
      style: const TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        color: _sceneNameColor,
        height: 1.15,
        shadows: overlayShadow,
      ),
    );
  }
}

/// A health bar: the whole track is always drawn, and the fill is the fraction
/// of health left, the same way the round timer reads.
class _Meter extends StatelessWidget {
  const _Meter({
    required this.label,
    required this.value,
    required this.gradient,
    this.semanticsValue,
  });

  final String label;
  final String? semanticsValue;
  final double value;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      value: semanticsValue,
      child: PillBar(value: value, gradient: gradient, height: 11.5),
    );
  }
}

class _CombatStage extends StatelessWidget {
  const _CombatStage({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final save = controller.save;
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
      scene: _TwoPortraits(
        player: _Portrait(
          assetPath: playerAssetPath(save.appearance),
          bytes: controller.localPlayerPng,
          semanticsLabel: 'Adventurer',
          alignment: Alignment.centerRight,
          overlay: round != null && (round.enemyHit ?? 0) > 0 && !controller.defeatedFlash
              ? _DamageFloater(
                  key: ValueKey('enemy-hit-$seq'),
                  text: '${round.enemyHit!.round()}',
                  color: _enemyHitColor,
                  alignment: const Alignment(-0.16, -0.16),
                  offset: _floaterOffset(seq, 1),
                )
              : null,
        ),
        scene: _Portrait(
          assetPath: controller.defeatedFlash ? null : enemyAssetPath(save.combatEnemyId!),
          semanticsLabel: enemyName,
          alignment: Alignment.centerLeft,
          placeholder: controller.defeatedFlash
              ? const Center(
                  child: Text(
                    'defeated',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: Color(0xFFFF3B3B),
                      shadows: overlayShadow,
                    ),
                  ),
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
                        alignment: const Alignment(0, -0.64),
                        offset: _floaterOffset(seq, 2),
                      ),
                    if (round != null && (round.offhandHit ?? 0) > 0)
                      _DamageFloater(
                        key: ValueKey('offhand-hit-$seq'),
                        text: '${round.offhandHit!.round()}',
                        color: _offhandHitColor,
                        alignment: const Alignment(0, -0.24),
                        offset: _floaterOffset(seq, 3),
                        fontSize: 17,
                      ),
                  ],
                ),
        ),
        // The player side has no name, but still leaves its line so both bars
        // sit at the same height.
        playerCaption: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            _Meter(
              label: 'Player health',
              semanticsValue: '${playerHp.round()} / ${maxHp.round()}',
              value: maxHp <= 0 ? 0 : (playerHp / maxHp).clamp(0, 1).toDouble(),
              gradient: Meters.playerHp,
            ),
          ],
        ),
        sceneCaption: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _SceneName(enemyName),
            const SizedBox(height: 3),
            _Meter(
              label: '$enemyName health',
              semanticsValue: '${enemyHp.round()} / ${enemyMaxHp.round()}',
              value: (enemyHp / enemyMaxHp).clamp(0, 1).toDouble(),
              gradient: Meters.enemyHp,
            ),
          ],
        ),
      ),
      // The timer stays through the defeat flash so the bar does not vanish
      // between one enemy and the next.
      footer: Semantics(
        label: 'Round progress',
        child: PillBar(
          value: controller.combatRoundProgress,
          gradient: Meters.combatRound,
          height: 8,
          borderColor: const Color(0x38FFECC4),
        ),
      ),
    );
  }
}

/// The death pause: no sprites, just the word for what the player is doing.
class _RecoveringStage extends StatelessWidget {
  const _RecoveringStage({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return _StageShell(
      semanticsLabel: 'Recovering',
      scene: _TwoPortraits(
        player: const _Portrait(
          assetPath: null,
          semanticsLabel: 'Recovering',
          alignment: Alignment.centerRight,
          placeholder: Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Recovering…',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Color(0xFFE0A080),
                shadows: overlayShadow,
              ),
            ),
          ),
        ),
        // Nothing fights back during the pause, so the other half stays empty.
        scene: const SizedBox(height: _portraitHeight),
        playerCaption: const SizedBox(height: 16),
        sceneCaption: const SizedBox(height: 16),
      ),
      footer: Text(
        'Resuming in ${formatDurationMs(controller.deathPauseRemainingMs)}',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Color(0xFFE0A080),
          shadows: overlayShadow,
        ),
      ),
    );
  }
}

/// The bar and the clock under a gathering or production scene.
class _ActionProgress extends StatelessWidget {
  const _ActionProgress({required this.progress, required this.durationMs});

  final double progress;
  final num durationMs;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Semantics(
            label: 'Action progress',
            child: PillBar(
              value: progress,
              gradient: Meters.action,
              height: 8,
              borderColor: const Color(0x38FFECC4),
            ),
          ),
        ),
        const SizedBox(width: 9),
        Text(
          '${formatDurationMs(durationMs * progress)} / ${formatDurationMs(durationMs)}',
          style: const TextStyle(fontSize: 12.5, color: _sceneNameColor, shadows: overlayShadow),
        ),
      ],
    );
  }
}

class _GatheringStage extends StatelessWidget {
  const _GatheringStage({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final save = controller.save;
    final action = save.currentActionId == null
        ? null
        : controller.indexes.actionsById[save.currentActionId!];
    final actionName = action?.displayName ?? 'Preparing…';
    final slow = action != null && isBelowProficiency(save, action);

    return _StageShell(
      semanticsLabel: 'Gathering',
      scene: _TwoPortraits(
        player: _Portrait(
          assetPath: playerAssetPath(save.appearance),
          bytes: controller.localPlayerPng,
          semanticsLabel: 'Adventurer',
          alignment: Alignment.centerRight,
        ),
        scene: _Portrait(
          assetPath: action == null ? null : actionAssetPath(action.actionId),
          semanticsLabel: actionName,
          alignment: Alignment.centerLeft,
          placeholder: action == null ? const SizedBox.expand() : null,
        ),
        playerCaption: const SizedBox(height: 16),
        sceneCaption: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _SceneName(actionName),
            if (slow)
              const Text(
                'this is tough work',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12.5, color: Palette.muted, shadows: overlayShadow),
              ),
          ],
        ),
      ),
      footer: _ActionProgress(
        progress: controller.actionProgress,
        durationMs: save.actionDurationMs ?? 0,
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
    final recipeId = save.productionRecipeId;
    final recipe = recipeId == null ? null : getRecipe(controller.db, recipeId);
    final popup = controller.craftPopup;
    final popupItem = popup == null ? null : controller.indexes.itemsById[popup.itemId];
    final stationName = recipe?.displayName ?? popup?.displayName ?? 'Workstation';

    return _StageShell(
      semanticsLabel: 'Production',
      scene: _TwoPortraits(
        player: _Portrait(
          assetPath: playerAssetPath(save.appearance),
          bytes: controller.localPlayerPng,
          semanticsLabel: 'Adventurer',
          alignment: Alignment.centerRight,
        ),
        scene: _Portrait(
          assetPath: workstationAssetPath(recipe?.facilityId),
          semanticsLabel: stationName,
          alignment: Alignment.centerLeft,
          overlay: popup == null
              ? null
              : Align(
                  alignment: const Alignment(0, -0.76),
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
        playerCaption: const SizedBox(height: 16),
        sceneCaption: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _SceneName(stationName),
            if (recipeId != null)
              Text(
                _queueLine(controller, recipeId),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Palette.muted,
                  shadows: overlayShadow,
                ),
              ),
          ],
        ),
      ),
      footer: _ActionProgress(
        progress: controller.actionProgress,
        durationMs: save.actionDurationMs ?? 0,
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
    this.fontSize = 21.5,
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

/// "3/10 · 7m 30s left" for a running craft queue.
String _queueLine(GameController controller, String recipeId) {
  final save = controller.save;
  final total = save.productionQuantityTotal ?? 0;
  final remaining = save.productionQuantityRemaining ?? 0;
  final craftMs = save.actionDurationMs ?? 0;
  final leftOfCurrent = craftMs * (1 - controller.actionProgress);
  final queuedAfter = remaining > 0 ? remaining - 1 : 0;
  return '${total - remaining}/$total · '
      '${formatDurationMs(leftOfCurrent + queuedAfter * craftMs)} left';
}

Offset _floaterOffset(int seq, int salt) {
  final mixed = seq * 31 + salt * 17;
  return Offset(((mixed % 49) - 24).toDouble(), (((mixed ~/ 7) % 37) - 18).toDouble());
}
