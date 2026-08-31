import 'dart:math' as math;

import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../save/generated/save_models.dart';
import '../time.dart';
import 'stats.dart';

const int defaultBossSleepRounds = 4;
const num defaultBossWakeHpRatio = 0.5;
const num defaultBossRampageHpRatio = 0.25;
const num defaultBossRespawnSeconds = 10;
const num defaultBossInkChance = 0.35;
const int defaultBossSquidlingCount = 3;

class BossProfile {
  const BossProfile({
    required this.sleepStart,
    required this.wakeHpRatio,
    required this.rampageHpRatio,
    required this.respawnSeconds,
    required this.squidlingsAt,
    required this.squidlingEnemyId,
    required this.squidlingCount,
    required this.inkAt,
    required this.inkChance,
    required this.damageMode,
    required this.playerBaseHpScale,
    required this.playerBaseDamagePctMin,
    required this.playerBaseDamagePctMax,
  });

  final int sleepStart;
  final num wakeHpRatio;
  final num rampageHpRatio;
  final num respawnSeconds;
  final num? squidlingsAt;
  final String? squidlingEnemyId;
  final int squidlingCount;
  final num? inkAt;
  final num inkChance;
  final String? damageMode;
  final num? playerBaseHpScale;
  final num? playerBaseDamagePctMin;
  final num? playerBaseDamagePctMax;
}

List<String> _noteTokens(Object? notes) {
  return jsString(notes)
      .split(';')
      .map((token) => token.trim())
      .where((token) => token.isNotEmpty)
      .toList();
}

num _noteNumber(List<String> tokens, String key, num fallback) {
  final prefix = '$key:';
  for (final token in tokens) {
    if (!token.toLowerCase().startsWith(prefix)) continue;
    final parsed = num.tryParse(token.substring(prefix.length).trim());
    if (parsed != null && parsed.isFinite) return parsed;
  }
  return fallback;
}

String? _noteString(List<String> tokens, String key, {String? fallback}) {
  final prefix = '$key:';
  for (final token in tokens) {
    if (!token.toLowerCase().startsWith(prefix)) continue;
    final value = token.substring(prefix.length).trim();
    if (value.isNotEmpty) return value;
  }
  return fallback;
}

bool isBossEnemy(EnemyRow? enemy) {
  if (enemy == null) return false;
  return _noteTokens(enemy.raw['Notes']).any((token) => token.toLowerCase() == 'boss');
}

BossProfile? bossProfile(EnemyRow? enemy) {
  if (!isBossEnemy(enemy)) return null;
  final tokens = _noteTokens(enemy!.raw['Notes']);
  final squidlingsAtRaw = _noteNumber(tokens, 'squidlings_at', double.nan);
  final inkAtRaw = _noteNumber(tokens, 'ink_at', double.nan);
  final hpScaleRaw = _noteNumber(tokens, 'player_base_hp_scale', double.nan);
  final dmgMinRaw = _noteNumber(tokens, 'player_base_damage_pct_min', double.nan);
  final dmgMaxRaw = _noteNumber(tokens, 'player_base_damage_pct_max', double.nan);
  final damageModeRaw = _noteString(tokens, 'damage_mode')?.toLowerCase();
  return BossProfile(
    sleepStart: math.max(0, _noteNumber(tokens, 'sleep_start', defaultBossSleepRounds).floor()),
    wakeHpRatio: _noteNumber(tokens, 'wake_hp_ratio', defaultBossWakeHpRatio),
    rampageHpRatio: _noteNumber(tokens, 'rampage_hp_ratio', defaultBossRampageHpRatio),
    respawnSeconds: math.max(0, _noteNumber(tokens, 'respawn_seconds', defaultBossRespawnSeconds)),
    squidlingsAt: squidlingsAtRaw.isFinite ? squidlingsAtRaw : null,
    squidlingEnemyId: _noteString(tokens, 'squidling_enemy'),
    squidlingCount: math.max(
      1,
      _noteNumber(tokens, 'squidling_count', defaultBossSquidlingCount).floor(),
    ),
    inkAt: inkAtRaw.isFinite ? inkAtRaw : null,
    inkChance: _noteNumber(tokens, 'ink_chance', defaultBossInkChance),
    damageMode: damageModeRaw == 'fishing' ? 'fishing' : null,
    playerBaseHpScale: hpScaleRaw.isFinite ? hpScaleRaw : null,
    playerBaseDamagePctMin: dmgMinRaw.isFinite ? dmgMinRaw : null,
    playerBaseDamagePctMax: dmgMaxRaw.isFinite ? dmgMaxRaw : null,
  );
}

num enemyEncounterMaxHp(GameDatabase db, PlayerSave save, EnemyRow enemy) {
  final profile = bossProfile(enemy);
  if (profile?.playerBaseHpScale != null) {
    return math.max(1, (playerBaseMaxHp(db, save) * profile!.playerBaseHpScale!).floor());
  }
  return jsNumber(enemy.raw['Maximum HP']);
}

({num min, num max})? _playerBaseDamagePctFromNotes(EnemyRow enemy) {
  final profile = bossProfile(enemy);
  if (profile?.playerBaseDamagePctMin != null && profile?.playerBaseDamagePctMax != null) {
    return (min: profile!.playerBaseDamagePctMin!, max: profile.playerBaseDamagePctMax!);
  }
  final tokens = _noteTokens(enemy.raw['Notes']);
  final dmgMinRaw = _noteNumber(tokens, 'player_base_damage_pct_min', double.nan);
  final dmgMaxRaw = _noteNumber(tokens, 'player_base_damage_pct_max', double.nan);
  if (!dmgMinRaw.isFinite || !dmgMaxRaw.isFinite) return null;
  return (min: dmgMinRaw, max: dmgMaxRaw);
}

DamageRange enemyEncounterDamageRange(GameDatabase db, PlayerSave save, EnemyRow enemy) {
  final pct = _playerBaseDamagePctFromNotes(enemy);
  if (pct != null) {
    final base = playerBaseMaxHp(db, save);
    final min = math.max(1, (base * pct.min / 100).floor());
    final max = math.max(min, (base * pct.max / 100).floor());
    return DamageRange(min: min, max: max);
  }
  return DamageRange(
    min: jsNumber(enemy.raw['Min Damage']),
    max: jsNumber(enemy.raw['Max Damage']),
  );
}

bool isBossAddFight(PlayerSave save) {
  return save.combatBossPendingId != null &&
      save.combatBossAddsRemaining != null &&
      (save.combatBossAddsRemaining ?? 0) > 0;
}

num? bossRespawnUntilMs(PlayerSave save, String enemyId) {
  final iso = save.bossRespawnUntilByEnemyId[enemyId];
  if (iso == null || iso.isEmpty) return null;
  final ms = jsDateParse(iso);
  return ms.isFinite ? ms : null;
}

bool isBossRespawnReady(PlayerSave save, String enemyId, num nowMs) {
  final until = bossRespawnUntilMs(save, enemyId);
  return until == null || nowMs >= until;
}

PlayerSave withBossRespawn(PlayerSave save, EnemyRow enemy, num nowMs) {
  final profile = bossProfile(enemy);
  if (profile == null) return save;
  return save.copyWith(
    bossRespawnUntilByEnemyId: <String, String>{
      ...save.bossRespawnUntilByEnemyId,
      jsString(enemy.raw['Enemy ID']): isoFromMs(nowMs + profile.respawnSeconds * 1000),
    },
  );
}

num applySleepIncoming(num damage, bool asleep) {
  if (!asleep) return damage;
  return (damage / 2).floor();
}
