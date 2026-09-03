import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

import '../content/asset_paths.dart';
import '../session/battery_saver_pref.dart';
import '../session/game_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'equipment_presets_bar.dart';
import 'game_image.dart';
import 'item_icon.dart';
import 'playable_frame.dart';

/// Portrait slot stays 152 so the stage does not jump between activities.
/// The player sprite is drawn smaller inside that slot; gathering scenes and
/// workstations are smaller still. Enemies keep the full slot.
const double _portraitSlotHeight = 152;
const double _playerArtHeight = 137;
const double _enemyArtHeight = 152;
const double _actionArtHeight = 152;
const double _captionMinHeight = 32;
const double _stageFooterHeight = 8;

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

/// Temporary stage lunge: wait 3.5s after the action starts, then a 1s hop
/// every 3.9s.
const int _stageHopDelayMs = 3500;
const int _stageHopPeriodMs = 3900;
const double _stageHopMotionEnd = 1000 / 3900;
const double _stageHopOutboundEnd = 0.55;
const double _stageHopInwardPx = 36;
const double _stageHopPeakPx = 16;
const double _stageHopRecoilPx = 10;

enum _StageHopKind { player, enemy, actionRecoil }

Offset _stageHopOffset(double t, _StageHopKind kind) {
  final clamped = t.clamp(0.0, 1.0);
  if (clamped >= _stageHopMotionEnd) return Offset.zero;
  final hopT = clamped / _stageHopMotionEnd;
  final inward = kind == _StageHopKind.actionRecoil ? _stageHopRecoilPx : _stageHopInwardPx;
  final peak = kind == _StageHopKind.actionRecoil ? 0.0 : _stageHopPeakPx;
  final xSign = kind == _StageHopKind.enemy ? -1.0 : 1.0;
  if (hopT <= _stageHopOutboundEnd) {
    final u = hopT / _stageHopOutboundEnd;
    return Offset(xSign * inward * u, -peak * 4 * u * (1 - u));
  }
  final u = (hopT - _stageHopOutboundEnd) / (1 - _stageHopOutboundEnd);
  return Offset(xSign * inward * (1 - u), 0);
}

/// Shared two-column stage for combat, gathering, and production.
///
/// Player art lives on [LocationIdlePlayer], under this stage, so the adventurer
/// stays on the location while idle. The right side is the enemy, the gathering
/// scene, or the workstation. Stopping lives on the activity row underneath.
class ActionStage extends StatelessWidget {
  const ActionStage({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    // Stage selection is mostly structural; meters/floaters need [progress].
    // Keep both, but the idle stand below no longer rebuilds every quiet tick.
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[controller, controller.progress]),
      builder: (context, _) {
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: playableHudTextScaler(MediaQuery.textScalerOf(context))),
          child: Builder(builder: _buildStage),
        );
      },
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

/// The adventurer on the location plate: combat-stage left slot, always shown
/// while standing here so they idle even when nothing is running. Gathering,
/// production, and combat scene art sit in the right slot on this same layer so
/// starting an action does not jump the PNGs.
class LocationIdlePlayer extends StatelessWidget {
  const LocationIdlePlayer({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    // Recovering is clock-driven ([progress]). While idle with no death hold,
    // only structural changes need a rebuild — do not repaint portraits every tick.
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.isRecovering && !controller.showingDeathHold) {
          return _buildIdle(context);
        }
        return ListenableBuilder(
          listenable: controller.progress,
          builder: (context, _) {
            if (controller.showRecoveringStage) return const SizedBox.shrink();
            return _buildIdle(context);
          },
        );
      },
    );
  }

  Widget _buildIdle(BuildContext context) {
    if (controller.showRecoveringStage) return const SizedBox.shrink();
    final save = controller.save;
    final maxHp = playerMaxHp(controller.db, save);
    final hp = save.currentHp;
    return MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: playableHudTextScaler(MediaQuery.textScalerOf(context))),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: 'Adventurer stand',
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 4, 2, 6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _stageMaxWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StageHopHost(
                  active: save.currentActivityId != null,
                  actionKey: save.currentActivityId,
                  child: _TwoPortraits(
                    player: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        EquipmentPresetsBar(
                          controller: controller,
                          axis: Axis.vertical,
                          compact: true,
                          showSaveButton: false,
                          allowLongPressEdit: false,
                          onMessage: controller.announce,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: IgnorePointer(
                            child: _playerWithPet(
                              save: save,
                              player: _Portrait(
                                assetPath: playerAssetPath(save.appearance, raceId: save.raceId),
                                bytes: controller.localPlayerPng,
                                semanticsLabel: 'Adventurer',
                                alignment: Alignment.centerRight,
                                height: _playerArtHeight,
                                slotHeight: _portraitSlotHeight,
                                filterQuality: FilterQuality.high,
                                hop: save.currentActivityId != null ? _StageHopKind.player : null,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    scene: _groundedSceneArt(controller),
                    playerCaption: ExcludeSemantics(
                      child: Opacity(
                        opacity: 0,
                        child: _FighterCaption(
                          name: save.characterName ?? 'Adventurer',
                          hpLabel: '${hp.round()}/${maxHp.round()}',
                          alignEnd: false,
                          meter: _Meter(
                            label: 'Player health',
                            value: maxHp <= 0 ? 0 : (hp / maxHp).clamp(0, 1).toDouble(),
                            gradient: Meters.hudHp,
                          ),
                        ),
                      ),
                    ),
                    sceneCaption: const SizedBox(height: _captionMinHeight),
                  ),
                ),
                const SizedBox(height: 7),
                const SizedBox(height: _stageFooterHeight),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Player art with an optional equipped pet sprite near the bottom-left.
Widget _playerWithPet({required PlayerSave save, required Widget player}) {
  final petId = save.cosmetics.equipped[petCosmeticSlotId];
  final petKey = petId == null ? null : critterKeyForPetCosmetic(petId);
  if (petKey == null) return player;
  return Stack(
    clipBehavior: Clip.none,
    alignment: Alignment.centerRight,
    children: [
      player,
      Positioned(
        left: 0,
        bottom: 8,
        child: GameImage(critterAssetPath(petKey), width: 36, height: 36),
      ),
    ],
  );
}

String _combatEnemyDisplayName(GameDatabase db, PlayerSave save, EnemyRow? enemy) {
  if (isBossAddFight(save) && save.combatBossPendingId != null) {
    final boss = getEnemy(db, save.combatBossPendingId!);
    final profile = boss != null ? bossProfile(boss) : null;
    final total = profile?.squidlingCount ?? save.combatBossAddsRemaining ?? 1;
    final remaining = save.combatBossAddsRemaining ?? 1;
    final index = total - remaining + 1;
    return 'Squidling ($index/$total)';
  }
  return enemy?.displayName ?? save.combatEnemyId ?? 'Enemy';
}

/// Right-slot art pinned with the adventurer: enemy, gather target, or station.
Widget _groundedSceneArt(GameController controller) {
  final save = controller.save;
  if (save.currentActivityId == null) {
    return const SizedBox(height: _portraitSlotHeight);
  }
  if (controller.defeatedFlash) {
    return const SizedBox(height: _portraitSlotHeight);
  }
  if (save.combatEnemyId != null || controller.combatBlowHold) {
    final enemyId = controller.stagedEnemyId ?? save.combatEnemyId;
    if (enemyId == null) return const SizedBox(height: _portraitSlotHeight);
    return _Portrait(
      assetPath: enemyAssetPath(enemyId),
      semanticsLabel: 'Enemy',
      height: _enemyArtHeight,
      slotHeight: _portraitSlotHeight,
      alignment: Alignment.centerLeft,
      hop: _StageHopKind.enemy,
    );
  }
  if (save.productionRecipeId != null || controller.craftPopup != null) {
    final recipeId = save.productionRecipeId;
    final recipe = recipeId == null ? null : getRecipe(controller.db, recipeId);
    return _Portrait(
      assetPath: workstationAssetPath(recipe?.facilityId),
      semanticsLabel: recipe?.displayName ?? 'Workstation',
      height: _actionArtHeight,
      slotHeight: _portraitSlotHeight,
      alignment: Alignment.bottomLeft,
      gaplessPlayback: true,
    );
  }
  final action = save.currentActionId == null
      ? null
      : controller.indexes.actionsById[save.currentActionId!];
  if (action == null) return const SizedBox(height: _portraitSlotHeight);
  return _Portrait(
    assetPath: actionAssetPath(action.actionId),
    semanticsLabel: action.displayName,
    height: _actionArtHeight,
    slotHeight: _portraitSlotHeight,
    alignment: Alignment.bottomLeft,
    gaplessPlayback: true,
    hop: _StageHopKind.actionRecoil,
  );
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
          slotHeight: _portraitSlotHeight,
          filterQuality: FilterQuality.high,
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
          slotHeight: _portraitSlotHeight,
          filterQuality: FilterQuality.high,
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
          height: _stageFooterHeight,
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
        // Size to the portraits — do not expand and re-center inside a tall
        // location slot, or the gathering PNG jumps when the stage appears.
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _stageMaxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [scene, const SizedBox(height: 7), footer],
          ),
        ),
      ),
    );
  }
}

class _InkSplatOverlay extends StatelessWidget {
  const _InkSplatOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.scale(scale: 0.82 + 0.18 * value, child: child),
        );
      },
      child: ColoredBox(
        color: const Color(0x73120818),
        child: Center(child: GameImage(uiInkSplatAssetPath(), width: 196, height: 196)),
      ),
    );
  }
}

/// Shared elapsed clock for both stage slots. The hop waits 3.5s after the
/// action starts, then plays in the first second of each 3.9s cycle.
class _StageHopHost extends StatefulWidget {
  const _StageHopHost({required this.active, required this.actionKey, required this.child});

  final bool active;
  final String? actionKey;
  final Widget child;

  @override
  State<_StageHopHost> createState() => _StageHopHostState();
}

class _StageHopHostState extends State<_StageHopHost> with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncClock();
  }

  @override
  void didUpdateWidget(covariant _StageHopHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.actionKey != widget.actionKey) {
      _stopTicker(reset: true);
    }
    _syncClock();
  }

  void _syncClock() {
    final reduceMotion = BatterySaverScope.of(context);
    if (!widget.active || reduceMotion) {
      _stopTicker(reset: true);
      return;
    }
    _startTicker();
  }

  void _startTicker() {
    if (_ticker != null) return;
    _ticker = createTicker((elapsed) {
      setState(() => _elapsed = elapsed);
    })..start();
  }

  void _stopTicker({required bool reset}) {
    _ticker?.dispose();
    _ticker = null;
    if (reset) _elapsed = Duration.zero;
  }

  double _periodT(Duration elapsed) {
    final ms = elapsed.inMilliseconds;
    if (ms < _stageHopDelayMs) return 1;
    return ((ms - _stageHopDelayMs) % _stageHopPeriodMs) / _stageHopPeriodMs;
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _StageHopTicker(t: _periodT(_elapsed), child: widget.child);
  }
}

class _StageHopTicker extends InheritedWidget {
  const _StageHopTicker({required this.t, required super.child});

  final double t;

  static double of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_StageHopTicker>()?.t ?? 0;
  }

  @override
  bool updateShouldNotify(_StageHopTicker oldWidget) => t != oldWidget.t;
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
    this.gaplessPlayback = false,
    this.hop,
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

  /// Keep the last frame while the next gathering action art loads.
  final bool gaplessPlayback;

  /// Temporary lunge; only the raster moves so the slot stays put.
  final _StageHopKind? hop;

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
                    gaplessPlayback: gaplessPlayback,
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
          clipBehavior: Clip.none,
          children: [
            ?placeholder,
            if (art != null)
              Align(
                alignment: Alignment.bottomCenter,
                child: Transform.translate(
                  offset: hop == null
                      ? Offset.zero
                      : _stageHopOffset(_StageHopTicker.of(context), hop!),
                  child: SizedBox(height: height, width: double.infinity, child: art),
                ),
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
        borderColor: const Color(0x599A7B32),
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
    final enemyName = _combatEnemyDisplayName(controller.db, save, enemy);
    final enemyMaxHp = math.max(
      1,
      enemy == null ? 1 : enemyEncounterMaxHp(controller.db, save, enemy).toInt(),
    );
    final enemyHp = controller.stagedEnemyHp;
    final maxHp = playerMaxHp(controller.db, save);
    final playerHp = controller.stagedPlayerHp;
    final round = controller.lastRound;
    final seq = controller.lastRoundSeq;
    final showFloaters = controller.showLastRoundFloaters;
    final ink = controller.inkPopup;

    final shell = _StageShell(
      semanticsLabel: 'Combat',
      scene: _TwoPortraits(
        player: SizedBox(
          height: _portraitSlotHeight,
          width: double.infinity,
          child:
              _playerFloaters(round, seq, showFloaters, controller.healPopup) ??
              const SizedBox.expand(),
        ),
        scene: _Portrait(
          assetPath: null,
          semanticsLabel: enemyName,
          height: _enemyArtHeight,
          slotHeight: _portraitSlotHeight,
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
              : const SizedBox.expand(),
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
          height: _stageFooterHeight,
          borderColor: const Color(0x38FFECC4),
        ),
      ),
    );
    if (ink == null) return shell;
    return Stack(
      alignment: Alignment.center,
      children: [
        shell,
        Positioned.fill(
          child: IgnorePointer(child: _InkSplatOverlay(key: ValueKey('ink-${ink.seq}'))),
        ),
      ],
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
          height: _playerArtHeight,
          slotHeight: _portraitSlotHeight,
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
        scene: const SizedBox(height: _portraitSlotHeight),
        playerCaption: const SizedBox(height: _captionMinHeight),
        sceneCaption: const SizedBox(height: _captionMinHeight),
      ),
      footer: Semantics(
        label: 'Resume progress',
        child: PillBar(
          value: controller.deathPauseProgress,
          gradient: Meters.combatRound,
          height: _stageFooterHeight,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${formatDurationMs(durationMs * progress)} / ${formatDurationMs(durationMs)}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5, color: _sceneNameColor, shadows: overlayShadow),
        ),
        const SizedBox(height: 4),
        Semantics(
          label: 'Action progress',
          child: PillBar(
            value: progress,
            gradient: Meters.action,
            height: _stageFooterHeight,
            borderColor: const Color(0x38FFECC4),
          ),
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
        player: const SizedBox(height: _portraitSlotHeight),
        scene: const SizedBox(height: _portraitSlotHeight),
        playerCaption: const SizedBox(height: _captionMinHeight),
        sceneCaption: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _captionMinHeight),
          child: Column(
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
        player: const SizedBox(height: _portraitSlotHeight),
        scene: _Portrait(
          assetPath: null,
          semanticsLabel: stationName,
          height: _actionArtHeight,
          slotHeight: _portraitSlotHeight,
          alignment: Alignment.bottomLeft,
          placeholder: const SizedBox.expand(),
          overlay: popup == null
              ? null
              : Align(
                  alignment: const Alignment(0, -0.76),
                  child: Semantics(
                    liveRegion: true,
                    label: popup.displayName,
                    child: ExcludeSemantics(
                      child: BatterySaverScope.of(context)
                          ? ItemIcon(item: popupItem, size: 38)
                          : TweenAnimationBuilder<double>(
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
        playerCaption: const SizedBox(height: _captionMinHeight),
        sceneCaption: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _captionMinHeight),
          child: Column(
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
    if (BatterySaverScope.of(context)) return const SizedBox.shrink();
    return _AnimatedDamageFloater(
      text: text,
      color: color,
      alignment: alignment,
      offset: offset,
      fontSize: fontSize,
    );
  }
}

class _AnimatedDamageFloater extends StatefulWidget {
  const _AnimatedDamageFloater({
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
  State<_AnimatedDamageFloater> createState() => _AnimatedDamageFloaterState();
}

class _AnimatedDamageFloaterState extends State<_AnimatedDamageFloater>
    with SingleTickerProviderStateMixin {
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
