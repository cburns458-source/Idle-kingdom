import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

import '../content/asset_paths.dart';
import '../session/game_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'game_image.dart';
import 'item_icon.dart';
import 'playable_frame.dart';

/// Player and enemy portraits stay this tall. Gathering and workstation art
/// sits in the same slot but is drawn smaller so the adventurer does not jump
/// when the activity type changes.
const double _playerArtHeight = 152;
const double _enemyArtHeight = 152;
const double _actionArtHeight = 72;

/// How wide either half of the stage can get, so the two sprites stay shoulder
/// to shoulder in the middle of a wide window instead of drifting apart.
const double _stageMaxWidth = 460;

const Color _playerHitColor = Color(0xFFFF8A3D);
const Color _critHitColor = Color(0xFFFFD166);
const Color _offhandHitColor = Color(0xFFF0A868);
const Color _staffHitColor = Color(0xFF6EC8FF);
const Color _enemyHitColor = Color(0xFFFFD0D0);
const Color _healColor = Color(0xFF7CFF9E);
const Color _foodHurtColor = Color(0xFFFF6B6B);
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
    return MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: playableHudTextScaler(MediaQuery.textScalerOf(context))),
      child: Builder(builder: _buildStage),
    );
  }

  Widget _buildStage(BuildContext context) {
    final save = controller.save;
    if (save.currentActivityId == null) return const SizedBox.shrink();
    // A death blow keeps the last fight on screen for a beat, then Recovering
    // takes over. Victory uses the same hold, then a short "defeated" banner.
    if (controller.showRecoveringStage) return _RecoveringStage(controller: controller);
    if (save.combatEnemyId != null || controller.combatBlowHold || controller.defeatedFlash) {
      return _CombatStage(controller: controller);
    }
    if (save.productionRecipeId != null || controller.craftPopup != null) {
      return _ProductionStage(controller: controller);
    }
    return _GatheringStage(controller: controller);
  }
}

/// Arena PvP, drawn with the same portraits, HUD bars, round meter, and floaters
/// as a PvE fight. The caller drives live 4s rounds.
class PvpActionStage extends StatelessWidget {
  const PvpActionStage({
    super.key,
    required this.youName,
    required this.themName,
    required this.youAppearance,
    required this.themAppearance,
    this.youRaceId,
    this.themRaceId,
    this.youBytes,
    required this.youHp,
    required this.youMaxHp,
    required this.themHp,
    required this.themMaxHp,
    required this.roundProgress,
    this.round,
    this.roundSeq = 0,
    this.finished = false,
  });

  final String youName;
  final String themName;
  final PlayerAppearance youAppearance;
  final PlayerAppearance themAppearance;
  final String? youRaceId;
  final String? themRaceId;
  final Uint8List? youBytes;
  final num youHp;
  final num youMaxHp;
  final num themHp;
  final num themMaxHp;
  final double roundProgress;
  final PvpRoundResult? round;
  final int roundSeq;
  final bool finished;

  @override
  Widget build(BuildContext context) {
    final youHit = round?.themHit ?? 0;
    final themHit = round?.youHit ?? 0;
    final themOffhand = round?.youOffhand ?? 0;
    return _StageShell(
      semanticsLabel: 'Arena combat',
      scene: _TwoPortraits(
        player: _Portrait(
          assetPath: playerAssetPath(youAppearance, raceId: youRaceId),
          bytes: youBytes,
          semanticsLabel: youName,
          alignment: Alignment.centerRight,
          height: _playerArtHeight,
          filterQuality: FilterQuality.medium,
          overlay: !finished && youHit > 0
              ? _DamageFloater(
                  key: ValueKey('pvp-them-hit-$roundSeq'),
                  text: '${youHit.round()}',
                  color: _enemyHitColor,
                  alignment: const Alignment(-0.16, -0.16),
                  offset: _floaterOffset(roundSeq, 1),
                )
              : null,
        ),
        scene: _Portrait(
          assetPath: playerAssetPath(themAppearance, raceId: themRaceId),
          semanticsLabel: themName,
          alignment: Alignment.centerLeft,
          height: _enemyArtHeight,
          filterQuality: FilterQuality.medium,
          flipX: true,
          overlay: finished
              ? null
              : Stack(
                  children: [
                    if (themHit > 0)
                      _DamageFloater(
                        key: ValueKey('pvp-you-hit-$roundSeq'),
                        text: round!.youCrit ? 'CRIT ${themHit.round()}' : '${themHit.round()}',
                        color: round!.youCrit ? _critHitColor : _playerHitColor,
                        alignment: const Alignment(0, -0.64),
                        offset: _floaterOffset(roundSeq, 2),
                      ),
                    if (themOffhand > 0)
                      _DamageFloater(
                        key: ValueKey('pvp-you-offhand-$roundSeq'),
                        text: '${themOffhand.round()}',
                        color: _offhandHitColor,
                        alignment: const Alignment(0, -0.24),
                        offset: _floaterOffset(roundSeq, 3),
                        fontSize: 17,
                      ),
                  ],
                ),
        ),
        playerCaption: _FighterCaption(
          name: youName,
          hpLabel: '${youHp.round()}/${youMaxHp.round()}',
          alignEnd: false,
          meter: _Meter(
            label: 'Player health',
            semanticsValue: '${youHp.round()} / ${youMaxHp.round()}',
            value: youMaxHp <= 0 ? 0 : (youHp / youMaxHp).clamp(0, 1).toDouble(),
            gradient: Meters.hudHp,
          ),
        ),
        sceneCaption: _FighterCaption(
          name: themName,
          hpLabel: '${themHp.round()}/${themMaxHp.round()}',
          alignEnd: true,
          meter: _Meter(
            label: '$themName health',
            semanticsValue: '${themHp.round()} / ${themMaxHp.round()}',
            value: themMaxHp <= 0 ? 0 : (themHp / themMaxHp).clamp(0, 1).toDouble(),
            gradient: Meters.hudHp,
          ),
        ),
      ),
      footer: Semantics(
        label: 'Round progress',
        child: PillBar(
          value: finished ? 1 : roundProgress.clamp(0, 1),
          gradient: Meters.combatRound,
          height: 8,
        ),
      ),
    );
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [player, const SizedBox(height: 5), playerCaption],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
    this.flipX = false,
    this.height = _playerArtHeight,
    this.slotHeight,
    this.filterQuality = FilterQuality.none,
  });

  final String? assetPath;
  final Uint8List? bytes;
  final String semanticsLabel;
  final Alignment alignment;
  final Widget? overlay;
  final Widget? placeholder;

  /// Arena opponents face the player. Damage numbers stay unflipped.
  final bool flipX;
  final double height;

  /// When set, the art is drawn at [height] inside a taller slot so the
  /// adventurer stays at a fixed 152px while action art sits smaller.
  final double? slotHeight;
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    final art = placeholder == null
        ? Transform.flip(
            flipX: flipX,
            child: bytes != null
                ? Image.memory(
                    bytes!,
                    fit: BoxFit.contain,
                    alignment: alignment,
                    filterQuality: filterQuality,
                    gaplessPlayback: true,
                  )
                : GameImage(
                    assetPath!,
                    fit: BoxFit.contain,
                    alignment: alignment,
                    filterQuality: filterQuality,
                  ),
          )
        : null;
    return Semantics(
      image: placeholder == null,
      label: semanticsLabel,
      child: SizedBox(
        height: slotHeight ?? height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ?placeholder,
            if (art != null)
              Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(height: height, width: double.infinity, child: art),
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
  const _SceneName(this.text, {this.alignEnd = true});

  final String text;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: alignEnd ? TextAlign.right : TextAlign.left,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w400,
        color: _sceneNameColor,
        height: 1.15,
        shadows: overlayShadow,
      ),
    );
  }
}

/// A health bar drawn like the HUD: the outline stays full width and the fill
/// shrinks as HP drops.
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
      child: PillBar(
        value: value,
        gradient: gradient,
        height: 8,
        trackColor: Palette.ink,
        borderColor: const Color(0x59D4AF37),
      ),
    );
  }
}

/// Name + HP so both fighters' bars sit on the same row.
class _FighterCaption extends StatelessWidget {
  const _FighterCaption({
    required this.name,
    required this.hpLabel,
    required this.alignEnd,
    required this.meter,
  });

  final String name;
  final String hpLabel;
  final bool alignEnd;
  final Widget meter;

  @override
  Widget build(BuildContext context) {
    final hpStyle = const TextStyle(fontSize: 11, color: Palette.muted);
    final nameRow = alignEnd
        ? Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(hpLabel, style: hpStyle),
              const SizedBox(width: 6),
              Flexible(child: _SceneName(name, alignEnd: true)),
            ],
          )
        : Row(
            children: [
              Flexible(child: _SceneName(name, alignEnd: false)),
              const SizedBox(width: 6),
              Text(hpLabel, style: hpStyle),
            ],
          );
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [nameRow, const SizedBox(height: 3), meter],
    );
  }
}

class _CombatStage extends StatelessWidget {
  const _CombatStage({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final save = controller.save;
    final enemyId = controller.stagedEnemyId ?? save.combatEnemyId;
    final enemy = enemyId == null ? null : getEnemy(controller.db, enemyId);
    final enemyName = enemy?.displayName ?? enemyId ?? 'Enemy';
    final enemyMaxHp = math.max(1, enemy?.maximumHp ?? 1);
    final enemyHp = controller.stagedEnemyHp;
    final maxHp = playerMaxHp(controller.db, save);
    final playerHp = controller.stagedPlayerHp;
    final round = controller.lastRound;
    final seq = controller.lastRoundSeq;
    final showFloaters = controller.showLastRoundFloaters;

    return _StageShell(
      semanticsLabel: 'Combat',
      scene: _TwoPortraits(
        player: _Portrait(
          assetPath: playerAssetPath(save.appearance, raceId: save.raceId),
          bytes: controller.localPlayerPng,
          semanticsLabel: 'Adventurer',
          alignment: Alignment.centerRight,
          height: _playerArtHeight,
          filterQuality: FilterQuality.medium,
          overlay: _playerFloaters(round, seq, showFloaters, controller.healPopup),
        ),
        scene: _Portrait(
          assetPath: controller.defeatedFlash || enemyId == null ? null : enemyAssetPath(enemyId),
          semanticsLabel: enemyName,
          height: _enemyArtHeight,
          alignment: Alignment.centerLeft,
          placeholder: controller.defeatedFlash
              ? const Center(
                  child: Text(
                    'defeated',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 1,
                      color: Color(0xFFFF3B3B),
                      shadows: overlayShadow,
                    ),
                  ),
                )
              : null,
          overlay: Stack(
            children: [
              if ((save.combatBossSleepRoundsRemaining ?? 0) > 0)
                const Align(
                  alignment: Alignment(0.18, -0.72),
                  child: Text(
                    'Zzz',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 1,
                      color: Color(0xFFB8D4FF),
                      shadows: overlayShadow,
                    ),
                  ),
                ),
              if (showFloaters && round != null && round.playerHit > 0)
                _DamageFloater(
                  key: ValueKey('player-hit-$seq'),
                  text: round.playerCrit
                      ? 'CRIT ${round.playerHit.round()}'
                      : '${round.playerHit.round()}',
                  color: round.playerCrit ? _critHitColor : _playerHitColor,
                  alignment: const Alignment(0, -0.64),
                  offset: _floaterOffset(seq, 2),
                ),
              if (showFloaters && round != null && (round.offhandHit ?? 0) > 0)
                _DamageFloater(
                  key: ValueKey('offhand-hit-$seq'),
                  text: '${round.offhandHit!.round()}',
                  color: _offhandHitColor,
                  alignment: const Alignment(0, -0.24),
                  offset: _floaterOffset(seq, 3),
                  fontSize: 17,
                ),
              if (showFloaters && round != null && (round.staffHit ?? 0) > 0)
                _DamageFloater(
                  key: ValueKey('staff-hit-$seq'),
                  text: '${round.staffHit!.round()}',
                  color: _staffHitColor,
                  alignment: const Alignment(0.18, -0.38),
                  offset: _floaterOffset(seq, 4),
                  fontSize: 17,
                ),
            ],
          ),
        ),
        playerCaption: _FighterCaption(
          name: save.characterName ?? 'Adventurer',
          hpLabel: '${playerHp.round()}/${maxHp.round()}',
          alignEnd: false,
          meter: _Meter(
            label: 'Player health',
            semanticsValue: '${playerHp.round()} / ${maxHp.round()}',
            value: maxHp <= 0 ? 0 : (playerHp / maxHp).clamp(0, 1).toDouble(),
            gradient: Meters.hudHp,
          ),
        ),
        sceneCaption: _FighterCaption(
          name: enemyName,
          hpLabel: '${enemyHp.round()}/${enemyMaxHp.round()}',
          alignEnd: true,
          meter: _Meter(
            label: '$enemyName health',
            semanticsValue: '${enemyHp.round()} / ${enemyMaxHp.round()}',
            value: (enemyHp / enemyMaxHp).clamp(0, 1).toDouble(),
            gradient: Meters.hudHp,
          ),
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
                fontWeight: FontWeight.w400,
                color: Color(0xFFE0A080),
                shadows: overlayShadow,
              ),
            ),
          ),
        ),
        // Nothing fights back during the pause, so the other half stays empty.
        scene: const SizedBox(height: _playerArtHeight),
        playerCaption: const SizedBox(height: 16),
        sceneCaption: const SizedBox(height: 16),
      ),
      footer: Semantics(
        label: 'Resume progress',
        child: PillBar(
          value: controller.deathPauseProgress,
          gradient: Meters.combatRound,
          height: 8,
          borderColor: const Color(0x38FFECC4),
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
          assetPath: playerAssetPath(save.appearance, raceId: save.raceId),
          bytes: controller.localPlayerPng,
          semanticsLabel: 'Adventurer',
          alignment: Alignment.centerRight,
          height: _playerArtHeight,
          filterQuality: FilterQuality.medium,
        ),
        scene: _Portrait(
          assetPath: action == null ? null : actionAssetPath(action.actionId),
          semanticsLabel: actionName,
          height: _actionArtHeight,
          slotHeight: _playerArtHeight,
          alignment: Alignment.centerLeft,
          placeholder: action == null ? const SizedBox.expand() : null,
        ),
        playerCaption: const SizedBox(height: 16),
        sceneCaption: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _SceneName(actionName),
            if (slow) ...[
              const Text(
                'this is tough work',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12.5, color: Palette.muted, shadows: overlayShadow),
              ),
              Text(
                'Recommended lvl ${formatThousands(action.proficiencyLevel ?? 1)}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Palette.muted,
                  shadows: overlayShadow,
                ),
              ),
            ],
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
          assetPath: playerAssetPath(save.appearance, raceId: save.raceId),
          bytes: controller.localPlayerPng,
          semanticsLabel: 'Adventurer',
          alignment: Alignment.centerRight,
          height: _playerArtHeight,
          filterQuality: FilterQuality.medium,
        ),
        scene: _Portrait(
          assetPath: workstationAssetPath(recipe?.facilityId),
          semanticsLabel: stationName,
          height: _actionArtHeight,
          slotHeight: _playerArtHeight,
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

class _DamageFloater extends StatefulWidget {
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
  State<_DamageFloater> createState() => _DamageFloaterState();
}

class _DamageFloaterState extends State<_DamageFloater> with SingleTickerProviderStateMixin {
  late final AnimationController _life;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _life = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: GameController.combatFloaterHoldMs),
    )..forward();
    _opacity = TweenSequence<double>([
      TweenSequenceItem<double>(tween: Tween<double>(begin: 0, end: 1), weight: 20),
      TweenSequenceItem<double>(tween: ConstantTween<double>(1), weight: 60),
      TweenSequenceItem<double>(tween: Tween<double>(begin: 1, end: 0), weight: 20),
    ]).animate(CurvedAnimation(parent: _life, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.alignment,
      child: Transform.translate(
        offset: widget.offset,
        child: FadeTransition(
          opacity: _opacity,
          child: Text(
            widget.text,
            style: TextStyle(
              fontSize: widget.fontSize,
              fontWeight: FontWeight.w400,
              color: widget.color,
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

/// Hits taken and food eaten, stacked so a heal after a win still shows.
Widget? _playerFloaters(CombatRoundEvent? round, int seq, bool showHits, HealPopup? heal) {
  final hit = showHits && round != null && (round.enemyHit ?? 0) > 0;
  if (!hit && heal == null) return null;
  return Stack(
    children: [
      if (hit)
        _DamageFloater(
          key: ValueKey('enemy-hit-$seq'),
          text: '${round.enemyHit!.round()}',
          color: _enemyHitColor,
          alignment: const Alignment(-0.16, -0.16),
          offset: _floaterOffset(seq, 1),
        ),
      if (heal != null)
        _DamageFloater(
          key: ValueKey('heal-${heal.seq}'),
          text: heal.amount > 0 ? '+${heal.amount.round()}' : '${heal.amount.round()}',
          color: heal.amount > 0 ? _healColor : _foodHurtColor,
          alignment: const Alignment(-0.08, -0.72),
          offset: _floaterOffset(heal.seq, 5),
        ),
    ],
  );
}

Offset _floaterOffset(int seq, int salt) {
  final mixed = seq * 31 + salt * 17;
  return Offset(((mixed % 49) - 24).toDouble(), (((mixed ~/ 7) % 37) - 18).toDouble());
}
