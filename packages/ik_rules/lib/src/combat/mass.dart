import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../config.dart';
import '../js_compat.dart';
import '../rng/mulberry32.dart';
import '../save/generated/save_models.dart';
import '../time.dart';
import '../vitals/regen.dart';
import 'boss.dart';
import 'boss_phase.dart';
import 'engine.dart';
import 'stats.dart';

export 'boss.dart' show massDropScale, massHealthMultiplier, massHpFor, massMinimumDamage;

class MassFightTickInput {
  const MassFightTickInput({
    required this.nowMs,
    required this.random,
    required this.encounterId,
    required this.enemyId,
    required this.sharedRemainingHp,
    required this.healthMultiplier,
    required this.lockedIn,
    required this.late,
    this.lastRoundStartedAt,
  });

  final num nowMs;
  final RandomFn random;
  final String encounterId;
  final String enemyId;
  final num sharedRemainingHp;
  final num healthMultiplier;
  final bool lockedIn;
  final bool late;
  final String? lastRoundStartedAt;
}

class MassFightTickResult {
  const MassFightTickResult({
    required this.save,
    required this.damageDealt,
    required this.early,
    required this.duplicate,
    required this.started,
    required this.kill,
    required this.defeated,
    this.roundStartedAt,
  });

  final PlayerSave save;
  final num damageDealt;
  final bool early;
  final bool duplicate;
  final bool started;
  final bool kill;
  final bool defeated;
  final String? roundStartedAt;
}

ActionRow? _actionForBoss(GameDatabase db, String enemyId) {
  return db.actions.firstWhereOrNull((row) => row.category == 'Combat' && row.targetId == enemyId);
}

num massSoloBaseHp(GameDatabase db, EnemyRow enemy, List<num> playerBaseHpValues) {
  final profile = bossProfile(enemy);
  final scale = profile?.playerBaseHpScale;
  if (scale != null) {
    final n = math.max(1, playerBaseHpValues.length);
    final sum = playerBaseHpValues.fold<num>(0, (total, value) => total + math.max(0, value));
    final avg = sum / n;
    return math.max(1, (avg * scale).floor());
  }
  return enemyScaledMaxHp(enemy);
}

({num soloHp, num healthMultiplier, num totalHp, num dropScale, num minDamage}) massEncounterHp(
  GameDatabase db,
  EnemyRow enemy,
  num lockedCount,
  List<num> playerBaseHpValues,
) {
  final n = math.max(1, lockedCount.floor());
  final soloHp = massSoloBaseHp(db, enemy, playerBaseHpValues);
  final healthMultiplier = massHealthMultiplier(n);
  final totalHp = massHpFor(soloHp, n);
  return (
    soloHp: soloHp,
    healthMultiplier: healthMultiplier,
    totalHp: totalHp,
    dropScale: massDropScale(n),
    minDamage: massMinimumDamage(totalHp, n),
  );
}

num? _roundEndMs(GameDatabase db, PlayerSave save) {
  if (isBlank(save.combatRoundStartedAt)) return null;
  final roundStart = jsDateParse(save.combatRoundStartedAt);
  if (!roundStart.toDouble().isFinite) return null;
  final roundMs = math.max(1, configNumber(db, 'combat_round_duration', 6) * 1000);
  return roundStart + roundMs;
}

/// One server-authoritative mass combat tick. Early or duplicate clocks add
/// no damage. Late joiners still fight locally but do not change shared HP.
MassFightTickResult simulateMassFightTick(
  GameDatabase db,
  PlayerSave save,
  MassFightTickInput input,
) {
  MassFightTickResult empty({PlayerSave? next, bool early = false, bool duplicate = false}) {
    final used = next ?? save;
    return MassFightTickResult(
      save: used,
      damageDealt: 0,
      early: early,
      duplicate: duplicate,
      started: false,
      kill: false,
      defeated: false,
      roundStartedAt: used.combatRoundStartedAt,
    );
  }

  if (!isMassBossEnemy(input.enemyId)) return empty();
  final enemy = getEnemy(db, input.enemyId);
  var action = _actionForBoss(db, input.enemyId);
  action ??= db.actions.firstWhereOrNull((row) => row.actionId == save.currentActionId);
  if (enemy == null || action == null) return empty();

  final nowIso = isoFromMs(input.nowMs);
  var next = save.massEncounterId == input.encounterId
      ? save
      : save.copyWith(massEncounterId: input.encounterId);

  if (isBlank(next.combatEnemyId) ||
      (next.combatEnemyId != input.enemyId &&
          next.combatBossPendingId != input.enemyId &&
          !isBossAddFight(next))) {
    next = beginCombatSave(
      db,
      next,
      action,
      enemy,
      nowIso,
      input.sharedRemainingHp,
    ).copyWith(massEncounterId: input.encounterId);
    return MassFightTickResult(
      save: next,
      damageDealt: 0,
      early: false,
      duplicate: false,
      started: true,
      kill: false,
      defeated: false,
      roundStartedAt: next.combatRoundStartedAt,
    );
  }

  final due = _roundEndMs(db, next);
  if (due == null || input.nowMs < due) {
    return empty(next: next, early: true);
  }
  if (input.lastRoundStartedAt != null && input.lastRoundStartedAt == next.combatRoundStartedAt) {
    return empty(next: next, duplicate: true);
  }

  final fightingAdds = isBossAddFight(next);
  final combatEnemy = getEnemy(db, next.combatEnemyId ?? input.enemyId) ?? enemy;
  final hpForRound = fightingAdds ? (next.combatEnemyHp ?? 0) : input.sharedRemainingHp;
  final roundStartedAt = next.combatRoundStartedAt;
  final round = resolveCombatRound(db, next, combatEnemy, hpForRound, input.random);

  var damageDealt = 0.0;
  if (!fightingAdds && input.lockedIn && !input.late) {
    damageDealt = math.max(0, input.sharedRemainingHp - round.enemyHp).toDouble();
  }
  final sharedAfter = math.max(0, input.sharedRemainingHp - damageDealt);

  var after = next.copyWith(
    combatEnemyHp: fightingAdds ? round.enemyHp : sharedAfter,
    currentHp: round.playerHp,
    combatPlayerSwingApplied: true,
    combatPendingRound: round.toPendingRound(),
    combatBossInkActive: round.bossInkActive,
    massEncounterId: input.encounterId,
  );
  if ((round.enemyHit ?? 0) > 0) {
    after = notePlayerDamaged(after, due);
  }

  if (round.outcome == 'defeat') {
    return MassFightTickResult(
      save: applyCombatDefeat(db, after.copyWith(currentHp: 0), due),
      damageDealt: damageDealt,
      early: false,
      duplicate: false,
      started: false,
      kill: false,
      defeated: true,
      roundStartedAt: roundStartedAt,
    );
  }

  if (round.outcome == 'victory' && isSquidlingVictory(after, combatEnemy)) {
    final squidling = applySquidlingVictory(
      db,
      after.copyWith(combatEnemyHp: 0, currentHp: round.playerHp),
      combatEnemy,
      isoFromMs(due),
      input.healthMultiplier,
    );
    var resumed = squidling.save.copyWith(massEncounterId: input.encounterId);
    if (squidling.bossResumed) {
      resumed = resumed.copyWith(combatEnemyHp: sharedAfter);
    }
    return MassFightTickResult(
      save: resumed,
      damageDealt: 0,
      early: false,
      duplicate: false,
      started: false,
      kill: false,
      defeated: false,
      roundStartedAt: roundStartedAt,
    );
  }

  if (round.bossAddsTriggered && round.bossPendingHp != null) {
    final profile = bossProfile(enemy);
    if (profile?.squidlingEnemyId != null) {
      final addsStarted = beginBossAddsEncounter(
        db,
        after.copyWith(currentHp: round.playerHp, combatBossInkActive: round.bossInkActive),
        enemy,
        profile!,
        sharedAfter,
        isoFromMs(due),
        input.healthMultiplier,
      );
      return MassFightTickResult(
        save: addsStarted.copyWith(massEncounterId: input.encounterId),
        damageDealt: damageDealt,
        early: false,
        duplicate: false,
        started: false,
        kill: sharedAfter <= 0,
        defeated: false,
        roundStartedAt: roundStartedAt,
      );
    }
  }

  if (round.outcome == 'victory' && !fightingAdds) {
    return MassFightTickResult(
      save: after.copyWith(combatEnemyHp: 0, massEncounterId: input.encounterId),
      damageDealt: damageDealt,
      early: false,
      duplicate: false,
      started: false,
      kill: sharedAfter <= 0,
      defeated: false,
      roundStartedAt: roundStartedAt,
    );
  }

  return MassFightTickResult(
    save: openCombatRoundClock(db, after, due).copyWith(
      combatSkipEnemyAttack: round.skipNextEnemyAttack,
      combatBossSleepRoundsRemaining: round.bossSleepRoundsRemaining,
      combatBossInkActive: round.bossInkActive,
      massEncounterId: input.encounterId,
    ),
    damageDealt: damageDealt,
    early: false,
    duplicate: false,
    started: false,
    kill: sharedAfter <= 0,
    defeated: false,
    roundStartedAt: roundStartedAt,
  );
}

CombatVictoryResult applyMassVictory(
  GameDatabase db,
  PlayerSave save,
  EnemyRow enemy,
  RandomFn random,
  num nowMs,
  num dropScale,
) {
  final action =
      _actionForBoss(db, jsString(enemy.raw['Enemy ID'])) ??
      db.actions.firstWhereOrNull((row) => row.actionId == save.currentActionId);
  if (action == null) {
    return applyCombatVictory(db, save, db.actions.first, enemy, random, nowMs, false, 0);
  }
  return applyCombatVictory(db, save, action, enemy, random, nowMs, false, dropScale);
}

String? massActivityIdForEnemy(String enemyId) => massBossEnemyActivity[enemyId];

class MassParticipantView {
  const MassParticipantView({
    required this.userId,
    required this.username,
    required this.late,
    required this.lockedIn,
    required this.present,
    required this.damageDealt,
  });

  final String userId;
  final String username;
  final bool late;
  final bool lockedIn;
  final bool present;
  final num damageDealt;

  factory MassParticipantView.fromJson(Map<String, Object?> json) {
    return MassParticipantView(
      userId: jsString(json['userId']),
      username: jsString(json['username']).isEmpty ? 'Adventurer' : jsString(json['username']),
      late: json['late'] == true,
      lockedIn: json['lockedIn'] == true,
      present: json['present'] == true,
      damageDealt: jsNumber(json['damageDealt'] ?? 0),
    );
  }
}

class MassYouView {
  const MassYouView({
    required this.late,
    required this.lockedIn,
    required this.present,
    required this.damageDealt,
    this.payoutEligible,
    required this.payoutClaimed,
    this.lastRoundStartedAt,
  });

  final bool late;
  final bool lockedIn;
  final bool present;
  final num damageDealt;
  final bool? payoutEligible;
  final bool payoutClaimed;
  final String? lastRoundStartedAt;

  factory MassYouView.fromJson(Map<String, Object?> json) {
    return MassYouView(
      late: json['late'] == true,
      lockedIn: json['lockedIn'] == true,
      present: json['present'] == true,
      damageDealt: jsNumber(json['damageDealt'] ?? 0),
      payoutEligible: json['payoutEligible'] is bool ? json['payoutEligible'] as bool : null,
      payoutClaimed: json['payoutClaimed'] == true,
      lastRoundStartedAt: json['lastRoundStartedAt'] is String
          ? json['lastRoundStartedAt'] as String
          : null,
    );
  }
}

class MassEncounterSnapshot {
  const MassEncounterSnapshot({
    required this.encounterId,
    required this.enemyId,
    required this.status,
    this.countdownEndsAt,
    this.spawnedAt,
    required this.lockedCount,
    required this.soloHp,
    required this.healthMultiplier,
    required this.totalHp,
    required this.remainingHp,
    required this.dropScale,
    required this.minDamage,
    this.lastLockedTickAt,
    this.closeReason,
    required this.participants,
    this.you,
  });

  final String encounterId;
  final String enemyId;
  final String status;
  final String? countdownEndsAt;
  final String? spawnedAt;
  final num lockedCount;
  final num soloHp;
  final num healthMultiplier;
  final num totalHp;
  final num remainingHp;
  final num dropScale;
  final num minDamage;
  final String? lastLockedTickAt;
  final String? closeReason;
  final List<MassParticipantView> participants;
  final MassYouView? you;

  bool get isLobby => status == 'lobby';
  bool get isFighting => status == 'fighting';

  factory MassEncounterSnapshot.fromJson(Map<String, Object?> json) {
    final rawYou = json['you'];
    return MassEncounterSnapshot(
      encounterId: jsString(json['encounterId']),
      enemyId: jsString(json['enemyId']),
      status: jsString(json['status']),
      countdownEndsAt: json['countdownEndsAt'] is String ? json['countdownEndsAt'] as String : null,
      spawnedAt: json['spawnedAt'] is String ? json['spawnedAt'] as String : null,
      lockedCount: jsNumber(json['lockedCount'] ?? 0),
      soloHp: jsNumber(json['soloHp'] ?? 0),
      healthMultiplier: jsNumber(json['healthMultiplier'] ?? 1),
      totalHp: jsNumber(json['totalHp'] ?? 0),
      remainingHp: jsNumber(json['remainingHp'] ?? 0),
      dropScale: jsNumber(json['dropScale'] ?? 1),
      minDamage: jsNumber(json['minDamage'] ?? 0),
      lastLockedTickAt: json['lastLockedTickAt'] is String
          ? json['lastLockedTickAt'] as String
          : null,
      closeReason: json['closeReason'] is String ? json['closeReason'] as String : null,
      participants: [
        for (final row in json['participants'] as List<Object?>? ?? const <Object?>[])
          if (row is Map) MassParticipantView.fromJson(Map<String, Object?>.from(row)),
      ],
      you: rawYou is Map ? MassYouView.fromJson(Map<String, Object?>.from(rawYou)) : null,
    );
  }

  static MassEncounterSnapshot? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, Object?>.from(raw);
    if (json['ok'] == false) return null;
    if (json['encounterId'] is! String || json['enemyId'] is! String) return null;
    return MassEncounterSnapshot.fromJson(json);
  }
}
