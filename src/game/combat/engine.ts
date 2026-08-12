import { configNumber } from '../activity/gathering'
import { resolveActionRewards } from '../activity/rewards'
import { applyXp } from '../activity/xp'
import type { ActionRow, GameDatabase } from '../data/types'
import type { EnemyRow } from '../data/enemyTypes'
import type { PlayerSave } from '../save/types'
import type { LootGrant } from '../activity/types'
import { tryConsumeFoodAfterVictory } from './food'
import {
  potionEnemyMaxHpDamage,
  tryConsumePotionForScope,
} from '../potions/effects'
import {
  criticalStrikeDamageMultiplier,
  equippedEnchantmentCritChancePercent,
  equippedEnchantmentThornsPercent,
} from '../projects/enchantments'
import { applyBountyDefeatProgress } from '../bounties/progress'
import { applyQuestDefeatProgress } from '../quests/progress'
import { applyRaceGoldGain } from '../races/races'
import {
  applyMitigation,
  playerDamageRange,
  playerDamageReduction,
  playerMaxHp,
  playerOffhandDamageRange,
  rollDamage,
} from './stats'

export type RandomFn = () => number

export interface CombatRoundResult {
  playerHit: number
  /** True when this round's main-hand hit was a critical strike. */
  playerCrit: boolean
  /** Off-hand dagger hit this round, or null when none / skipped. */
  offhandHit: number | null
  enemyHit: number | null
  /** Damage reflected back at the enemy this round via armor enchantments (e.g. Thorns). */
  thornsHit: number
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
  const potion = tryConsumePotionForScope(db, save, 'one_combat_encounter')
  const poisonDamage = potionEnemyMaxHpDamage(enemy['Maximum HP'], potion.effect)
  const enemyHp = Math.max(0, enemy['Maximum HP'] - poisonDamage)
  return {
    ...potion.save,
    currentActionId: action['Action ID'],
    actionStartedAt: nowIso,
    actionDurationMs: null,
    combatEnemyId: enemy['Enemy ID'],
    combatEnemyHp: enemyHp,
    combatRoundStartedAt: nowIso,
    activePotionEffect: potion.effect,
    deathPauseUntil: null,
  }
}

export function clearCombatSave(save: PlayerSave): PlayerSave {
  return {
    ...save,
    combatEnemyId: null,
    combatEnemyHp: null,
    combatRoundStartedAt: null,
    activePotionEffect:
      save.activePotionEffect?.scope === 'one_combat_encounter' ? null : save.activePotionEffect,
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
  let playerHit = rollDamage(playerRange.min, playerRange.max, random)
  let playerCrit = false
  const critChance = equippedEnchantmentCritChancePercent(db, save)
  if (critChance > 0 && random() * 100 < critChance) {
    playerCrit = true
    playerHit = Math.max(1, Math.floor(playerHit * criticalStrikeDamageMultiplier()))
  }
  let nextEnemyHp = Math.max(0, enemyHp - playerHit)

  // Off-hand dagger swings after the main-hand hit if the enemy is still up.
  // Off-hand cannot crit; shared enchant/spell bonuses are already in its range.
  let offhandHit: number | null = null
  if (nextEnemyHp > 0) {
    const offhandRange = playerOffhandDamageRange(db, save)
    if (offhandRange) {
      offhandHit = rollDamage(offhandRange.min, offhandRange.max, random)
      nextEnemyHp = Math.max(0, nextEnemyHp - offhandHit)
    }
  }

  if (nextEnemyHp <= 0) {
    return {
      playerHit,
      playerCrit,
      offhandHit,
      enemyHit: null,
      thornsHit: 0,
      enemyHp: 0,
      playerHp: save.currentHp,
      outcome: 'victory',
    }
  }

  const enemyRaw = rollDamage(enemy['Min Damage'], enemy['Max Damage'], random)
  const enemyHit = applyMitigation(enemyRaw, playerDamageReduction(db, save), floor)
  const playerHp = Math.max(0, save.currentHp - enemyHit)

  const thornsPercent = equippedEnchantmentThornsPercent(db, save)
  const thornsHit = thornsPercent > 0 ? Math.round((enemyHit * thornsPercent) / 100) : 0
  if (thornsHit > 0) {
    nextEnemyHp = Math.max(0, nextEnemyHp - thornsHit)
  }

  return {
    playerHit,
    playerCrit,
    offhandHit,
    enemyHit,
    thornsHit,
    enemyHp: nextEnemyHp,
    playerHp,
    // Simultaneous kills favor defeat: the enemy's own hit must land before Thorns reflects it.
    outcome: playerHp <= 0 ? 'defeat' : nextEnemyHp <= 0 ? 'victory' : 'ongoing',
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
    const racedGold = applyRaceGoldGain(db, save, goldRoll)
    next = { ...next, gold: next.gold + racedGold }
    goldGained += racedGold
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
  next = applyQuestDefeatProgress(db, next, enemy['Enemy ID'], 1)
  next = applyBountyDefeatProgress(next, enemy['Enemy ID'], 1)

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
