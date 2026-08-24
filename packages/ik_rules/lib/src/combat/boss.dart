import 'dart:math' as math;

import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../save/generated/save_models.dart';
import '../time.dart';

const int defaultBossSleepRounds = 4;
const num defaultBossWakeHpRatio = 0.5;
const num defaultBossRampageHpRatio = 0.25;
const num defaultBossRespawnSeconds = 10;

class BossProfile {
  const BossProfile({
    required this.sleepStart,
    required this.wakeHpRatio,
    required this.rampageHpRatio,
    required this.respawnSeconds,
  });

  final int sleepStart;
  final num wakeHpRatio;
  final num rampageHpRatio;
  final num respawnSeconds;
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

bool isBossEnemy(EnemyRow? enemy) {
  if (enemy == null) return false;
  return _noteTokens(enemy.raw['Notes']).any((token) => token.toLowerCase() == 'boss');
}

BossProfile? bossProfile(EnemyRow? enemy) {
  if (!isBossEnemy(enemy)) return null;
  final tokens = _noteTokens(enemy!.raw['Notes']);
  return BossProfile(
    sleepStart: math.max(0, _noteNumber(tokens, 'sleep_start', defaultBossSleepRounds).floor()),
    wakeHpRatio: _noteNumber(tokens, 'wake_hp_ratio', defaultBossWakeHpRatio),
    rampageHpRatio: _noteNumber(tokens, 'rampage_hp_ratio', defaultBossRampageHpRatio),
    respawnSeconds: math.max(0, _noteNumber(tokens, 'respawn_seconds', defaultBossRespawnSeconds)),
  );
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
