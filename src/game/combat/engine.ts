import { configNumber } from '../activity/gathering'
import { resolveActionRewards } from '../activity/rewards'
import { applyXp } from '../activity/xp'
import type { ActionRow, GameDatabase } from '../data/types'
import type { EnemyRow } from '../data/enemyTypes'
import type { PlayerSave } from '../save/types'
import type { LootGrant } from '../activity/types'
import { tryConsumeFoodAfterVictory } from './food'
import { tryConsumeCombatEncounterPotion } from './potion'
import {
  applyMitigation,
  playerDamageRange,
  playerDamageReduction,
  playerMaxHp,
  rollDamage,
} from './stats'

export type RandomFn = () => number

export interface CombatRoundResult {
  playerHit: number
  enemyHit: number | null
  enemyHp: number
  playerHp: number
  outcome: 'ongoing' | 'victory' | 'defeat'
}

export interface CombatVictoryResult {
  save: PlayerSave
  xpGained: number
  goldGained: number
  loot: LootGrant[]
  foodConsumed: boolean
  foodHealed: number
  foodName: string | null
}

export function getEnemy(db: GameDatabase, enemyId: string): EnemyRow | undefined {
  return db.Enemies.find((row) => row['Enemy ID'] === enemyId)
}

export function enemyForAction(db: GameDatabase, action: ActionRow): EnemyRow | undefined {
  if (action.Category !== 'Combat' || !action['Target ID']) return undefined
  return getEnemy(db, action['Target ID'])
}

export function beginCombatSave(
  db: GameDatabase,
  save: PlayerSave,
  action: ActionRow,
  enemy: EnemyRow,
  nowIso: string = new Date().toISOString(),
): PlayerSave {
  const potion = tryConsumeCombatEncounterPotion(db, save)
  return {
    ...potion.save,
    currentActionId: action['Action ID'],
    actionStartedAt: nowIso,
    actionDurationMs: null,
    combatEnemyId: enemy['Enemy ID'],
    combatEnemyHp: enemy['Maximum HP'],
    combatRoundStartedAt: nowIso,
    combatPotionDamageBonusPercent: potion.consumed ? potion.damageBonusPercent : null,
    deathPauseUntil: null,
  }
}

export function clearCombatSave(save: PlayerSave): PlayerSave {
  return {
    ...save,
    combatEnemyId: null,
    combatEnemyHp: null,
    combatRoundStartedAt: null,
    combatPotionDamageBonusPercent: null,
  }
}

export function resolveCombatRound(
  db: GameDatabase,
  save: PlayerSave,
  enemy: EnemyRow,
  enemyHp: number,
  random: RandomFn = Math.random,
): CombatRoundResult {
  const floor = configNumber(db, 'damage_floor', 1)
  const playerRange = playerDamageRange(db, save)
  const playerHit = rollDamage(playerRange.min, playerRange.max, random)
  let nextEnemyHp = Math.max(0, enemyHp - playerHit)

  if (nextEnemyHp <= 0) {
    return {
      playerHit,
      enemyHit: null,
      enemyHp: 0,
      playerHp: save.currentHp,
      outcome: 'victory',
    }
  }

  const enemyRaw = rollDamage(enemy['Min Damage'], enemy['Max Damage'], random)
  const enemyHit = applyMitigation(enemyRaw, playerDamageReduction(db, save), floor)
  const playerHp = Math.max(0, save.currentHp - enemyHit)

  return {
    playerHit,
    enemyHit,
    enemyHp: nextEnemyHp,
    playerHp,
    outcome: playerHp <= 0 ? 'defeat' : 'ongoing',
  }
}

export function applyCombatVictory(
  db: GameDatabase,
  save: PlayerSave,
  action: ActionRow,
  enemy: EnemyRow,
  random: RandomFn = Math.random,
): CombatVictoryResult {
  const maxHp = playerMaxHp(db, save)
  let next: PlayerSave = { ...save, maxHp, currentHp: Math.min(save.currentHp, maxHp) }

  const xpAmount = Number(enemy['Combat XP'] ?? action['XP Reward'] ?? 0)
  const xpApplied = applyXp(next, db, 'SKL-0001', xpAmount)
  next = xpApplied.save

  const minGold = Number(enemy['Minimum Gold'] ?? 0)
  const maxGold = Number(enemy['Maximum Gold'] ?? minGold)
  const goldRoll =
    maxGold > minGold ? minGold + Math.floor(random() * (maxGold - minGold + 1)) : minGold

  // Use action reward table / drop chance (aligned with enemy table in data).
  const rewarded = resolveActionRewards(db, next, action, random)
  next = rewarded.save
  let goldGained = rewarded.goldGained
  if (goldRoll > 0) {
    next = { ...next, gold: next.gold + goldRoll }
    goldGained += goldRoll
  }

  const kills = Number(next.statistics.values.monsters_killed ?? 0) + 1
  const goldEarned = Number(next.statistics.values.gold_earned ?? 0) + goldGained
  next = {
    ...next,
    statistics: {
      values: {
        ...next.statistics.values,
        monsters_killed: kills,
        gold_earned: goldEarned,
      },
    },
  }

  const food = tryConsumeFoodAfterVictory(db, next)
  next = clearCombatSave(food.save)

  return {
    save: next,
    xpGained: xpAmount,
    goldGained,
    loot: rewarded.loot,
    foodConsumed: food.consumed,
    foodHealed: food.healed,
    foodName: food.foodName,
  }
}

export function applyCombatDefeat(
  db: GameDatabase,
  save: PlayerSave,
  nowMs: number = Date.now(),
): PlayerSave {
  const pauseSec = configNumber(db, 'death_pause', 30)
  const maxHp = playerMaxHp(db, save)
  return clearCombatSave({
    ...save,
    maxHp,
    currentHp: maxHp,
    deathPauseUntil: new Date(nowMs + pauseSec * 1000).toISOString(),
    currentActionId: null,
    actionStartedAt: null,
    actionDurationMs: null,
  })
}

export function isDeathPaused(save: PlayerSave, nowMs: number = Date.now()): boolean {
  if (!save.deathPauseUntil) return false
  return Date.parse(save.deathPauseUntil) > nowMs
}

export function deathPauseRemainingMs(save: PlayerSave, nowMs: number = Date.now()): number {
  if (!save.deathPauseUntil) return 0
  return Math.max(0, Date.parse(save.deathPauseUntil) - nowMs)
}
