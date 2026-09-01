import { applyXp } from '../activity/xp'
import { FISHING_SKILL_ID } from '../skills/skillActions'
import type { GameDatabase } from '../data/types'
import type { EnemyRow } from '../data/enemyTypes'
import type { PlayerSave } from '../save/types'
import { recordEnemyKill } from '../achievements/progress'
import { bossProfile, isBossAddFight, type BossProfile } from './boss'
import { getEnemy } from './engine'

export interface SquidlingVictoryResult {
  save: PlayerSave
  xpGained: number
  /** Always Fishing for Squidling kills. */
  xpSkillId: string
  message: string
  /** True when the boss resumes; false when another add remains. */
  bossResumed: boolean
}

export function beginBossAddsEncounter(
  db: GameDatabase,
  save: PlayerSave,
  bossEnemy: EnemyRow,
  profile: BossProfile,
  pendingHp: number,
  roundEndIso: string,
): PlayerSave {
  const squidling = getEnemy(db, profile.squidlingEnemyId!)
  if (!squidling) return save
  return {
    ...save,
    combatBossPendingId: bossEnemy['Enemy ID'],
    combatBossPendingHp: pendingHp,
    combatBossAddsRemaining: profile.squidlingCount,
    combatBossAddsTriggered: true,
    combatBossInkActive: false,
    combatEnemyId: squidling['Enemy ID'],
    combatEnemyHp: squidling['Maximum HP'],
    combatRoundStartedAt: roundEndIso,
    combatSkipEnemyAttack: false,
    combatBossSleepRoundsRemaining: null,
  }
}

export function applySquidlingVictory(
  db: GameDatabase,
  save: PlayerSave,
  squidling: EnemyRow,
  roundEndIso: string,
): SquidlingVictoryResult {
  const xpAmount = Number(squidling['Combat XP'] ?? 0)
  let next = applyXp(save, db, FISHING_SKILL_ID, xpAmount).save
  const kills = Number(next.statistics.values.monsters_killed ?? 0) + 1
  next = {
    ...next,
    statistics: {
      values: {
        ...next.statistics.values,
        monsters_killed: kills,
      },
    },
  }
  next = recordEnemyKill(db, next, squidling['Enemy ID'])

  const remaining = Math.max(0, (next.combatBossAddsRemaining ?? 1) - 1)
  const bossId = next.combatBossPendingId
  const pendingHp = next.combatBossPendingHp ?? 0

  if (remaining > 0 && bossId) {
    const profile = bossProfile(getEnemy(db, bossId))
    const nextSquidling =
      profile?.squidlingEnemyId != null ? getEnemy(db, profile.squidlingEnemyId) : undefined
    if (!nextSquidling) {
      return { save: next, xpGained: xpAmount, xpSkillId: FISHING_SKILL_ID, message: 'Squidling defeated.', bossResumed: false }
    }
    const total = profile?.squidlingCount ?? remaining + 1
    const defeated = total - remaining
    return {
      save: {
        ...next,
        combatBossAddsRemaining: remaining,
        combatEnemyId: nextSquidling['Enemy ID'],
        combatEnemyHp: nextSquidling['Maximum HP'],
        combatRoundStartedAt: roundEndIso,
        combatBossInkActive: false,
        combatSkipEnemyAttack: false,
      },
      xpGained: xpAmount,
      xpSkillId: FISHING_SKILL_ID,
      message: `Squidling defeated (${defeated}/${total}). Another emerges!`,
      bossResumed: false,
    }
  }

  if (!bossId) {
    return { save: next, xpGained: xpAmount, xpSkillId: FISHING_SKILL_ID, message: 'Squidling defeated.', bossResumed: false }
  }

  const boss = getEnemy(db, bossId)
  if (!boss) {
    return { save: next, xpGained: xpAmount, xpSkillId: FISHING_SKILL_ID, message: 'Squidling defeated.', bossResumed: false }
  }

  return {
    save: {
      ...next,
      combatBossAddsRemaining: null,
      combatBossPendingId: null,
      combatBossPendingHp: null,
      combatEnemyId: bossId,
      combatEnemyHp: pendingHp,
      combatRoundStartedAt: roundEndIso,
      combatBossInkActive: false,
      combatSkipEnemyAttack: false,
      combatBossSleepRoundsRemaining: null,
    },
    xpGained: xpAmount,
      xpSkillId: FISHING_SKILL_ID,
    message: `Squidling defeated. ${boss['Display Name']} returns at ${pendingHp} HP!`,
    bossResumed: true,
  }
}

export function isSquidlingVictory(save: PlayerSave, enemy: EnemyRow): boolean {
  if (!isBossAddFight(save)) return false
  return save.combatEnemyId === enemy['Enemy ID']
}
