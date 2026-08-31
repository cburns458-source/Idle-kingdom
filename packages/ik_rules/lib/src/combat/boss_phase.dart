import 'dart:math' as math;

import 'package:ik_content/ik_content.dart';

import '../achievements/progress.dart';
import '../activity/xp.dart';
import '../skills/skill_actions.dart' show fishingSkillId;
import '../save/generated/save_models.dart';
import 'boss.dart';
import 'engine.dart';

class SquidlingVictoryResult {
  const SquidlingVictoryResult({
    required this.save,
    required this.xpGained,
    required this.message,
    required this.bossResumed,
  });

  final PlayerSave save;
  final num xpGained;
  final String message;
  final bool bossResumed;
}

PlayerSave beginBossAddsEncounter(
  GameDatabase db,
  PlayerSave save,
  EnemyRow bossEnemy,
  BossProfile profile,
  num pendingHp,
  String roundEndIso,
) {
  final squidling = getEnemy(db, profile.squidlingEnemyId!);
  if (squidling == null) return save;
  return save.copyWith(
    combatBossPendingId: bossEnemy.raw['Enemy ID'] as String?,
    combatBossPendingHp: pendingHp,
    combatBossAddsRemaining: profile.squidlingCount,
    combatBossAddsTriggered: true,
    combatBossInkActive: false,
    combatEnemyId: squidling.raw['Enemy ID'] as String?,
    combatEnemyHp: squidling.maximumHp,
    combatRoundStartedAt: roundEndIso,
    combatSkipEnemyAttack: false,
    combatBossSleepRoundsRemaining: null,
  );
}

SquidlingVictoryResult applySquidlingVictory(
  GameDatabase db,
  PlayerSave save,
  EnemyRow squidling,
  String roundEndIso,
) {
  final xpAmount = squidling.combatXp ?? 0;
  var next = applyXp(save, db, fishingSkillId, xpAmount).save;
  final kills = (next.statistics.values['monsters_killed'] ?? 0) + 1;
  next = next.copyWith(
    statistics: PlayerStatistics(
      values: <String, num>{...next.statistics.values, 'monsters_killed': kills},
    ),
  );
  next = recordEnemyKill(db, next, squidling.raw['Enemy ID'] as String);

  final remaining = math.max(0, (next.combatBossAddsRemaining ?? 1) - 1);
  final bossId = next.combatBossPendingId;
  final pendingHp = next.combatBossPendingHp ?? 0;

  if (remaining > 0 && bossId != null) {
    final profile = bossProfile(getEnemy(db, bossId));
    final nextSquidling = profile?.squidlingEnemyId != null
        ? getEnemy(db, profile!.squidlingEnemyId!)
        : null;
    if (nextSquidling == null) {
      return SquidlingVictoryResult(
        save: next,
        xpGained: xpAmount,
        message: 'Squidling defeated.',
        bossResumed: false,
      );
    }
    final total = profile?.squidlingCount ?? remaining + 1;
    final defeated = total - remaining;
    return SquidlingVictoryResult(
      save: next.copyWith(
        combatBossAddsRemaining: remaining,
        combatEnemyId: nextSquidling.raw['Enemy ID'] as String?,
        combatEnemyHp: nextSquidling.maximumHp,
        combatRoundStartedAt: roundEndIso,
        combatBossInkActive: false,
        combatSkipEnemyAttack: false,
      ),
      xpGained: xpAmount,
      message: 'Squidling defeated ($defeated/$total). Another emerges!',
      bossResumed: false,
    );
  }

  if (bossId == null) {
    return SquidlingVictoryResult(
      save: next,
      xpGained: xpAmount,
      message: 'Squidling defeated.',
      bossResumed: false,
    );
  }

  final boss = getEnemy(db, bossId);
  if (boss == null) {
    return SquidlingVictoryResult(
      save: next,
      xpGained: xpAmount,
      message: 'Squidling defeated.',
      bossResumed: false,
    );
  }

  return SquidlingVictoryResult(
    save: next.copyWith(
      combatBossAddsRemaining: null,
      combatBossPendingId: null,
      combatBossPendingHp: null,
      combatEnemyId: bossId,
      combatEnemyHp: pendingHp,
      combatRoundStartedAt: roundEndIso,
      combatBossInkActive: false,
      combatSkipEnemyAttack: false,
      combatBossSleepRoundsRemaining: null,
    ),
    xpGained: xpAmount,
    message: 'Squidling defeated. ${boss.displayName} returns at $pendingHp HP!',
    bossResumed: true,
  );
}

bool isSquidlingVictory(PlayerSave save, EnemyRow enemy) {
  if (!isBossAddFight(save)) return false;
  return save.combatEnemyId == enemy.raw['Enemy ID'];
}
