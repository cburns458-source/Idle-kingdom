import { recordEnemyKill } from '../achievements/progress'
import { withoutHeldAction } from '../activity/heldAction'
import { configNumber } from '../activity/gathering'
import { resolveActionRewards } from '../activity/rewards'
import { applyXp, getSkillProgress } from '../activity/xp'
import type { ActionRow, GameDatabase } from '../data/types'
import type { EnemyRow } from '../data/enemyTypes'
import { revokeCosmetic } from '../cosmetics/cosmetics'
import { STARTER_TITLE_COSMETIC_ID } from '../save/types'
import type { PlayerSave } from '../save/types'
import type { LootGrant } from '../activity/types'
import { consumeFoodAfterVictory } from './food'
import { applyPotionEnemyRoundDamage, tryConsumePotionForScope } from '../potions/effects'
import {
  criticalStrikeDamageMultiplier,
  equippedEnchantmentCritChancePercent,
  equippedEnchantmentThornsPercent,
} from '../projects/enchantments'
import { applyBountyDefeatProgress } from '../bounties/progress'
import { applyQuestDefeatProgress } from '../quests/progress'
import { applyRaceGoldGain } from '../races/races'
import { itemHasCapability, WEAPON_TOOL_SLOT_ID } from '../equipment/loadout'
import { currentHpAfterMaxChange } from '../equipment/vitals'
import { ARCANA_SKILL_ID } from '../npcs/knowledge'
import {
  applyMitigation,
  fishingCombatDamageRange,
  playerDamageRange,
  playerDamageReduction,
  playerMaxHp,
  playerOffhandDamageRange,
  rollDamage,
  staffSparksDamageRange,
} from './stats'
import { applySleepIncoming, bossProfile, enemyEncounterDamageRange, enemyEncounterMaxHp, isBossAddFight, withBossRespawn } from './boss'

export type RandomFn = () => number

export interface CombatRoundResult {
  playerHit: number
  /** True when this round's main-hand hit was a critical strike. */
  playerCrit: boolean
  /** Off-hand dagger hit this round, or null when none / skipped. */
  offhandHit: number | null
  /** Staff of Sparks extra hit this round, or null when none / skipped. */
  staffHit: number | null
  /** Persist Binding: skip the enemy's next attack. */
  skipNextEnemyAttack: boolean
  enemyHit: number | null
  /** Damage reflected back at the enemy this round via armor enchantments (e.g. Thorns). */
  thornsHit: number
  /** Remaining boss sleep rounds after this one, or null when the enemy is not a boss. */
  bossSleepRoundsRemaining: number | null
  /** True when this enemy started the round asleep. */
  enemyAsleep: boolean
  /** True when the enemy's landing swing was a rampage hit. */
  enemyRampage: boolean
  /** True when this round triggered a boss add phase (e.g. squidlings). */
  bossAddsTriggered: boolean
  /** True when ink halved player damage this round. */
  bossInkActive: boolean
  /** HP to restore on the boss when adds finish. Set when bossAddsTriggered. */
  bossPendingHp: number | null
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
  return {
    ...potion.save,
    currentActionId: action['Action ID'],
    actionStartedAt: nowIso,
    actionDurationMs: null,
    combatEnemyId: enemy['Enemy ID'],
    combatEnemyHp: enemyEncounterMaxHp(db, potion.save, enemy),
    combatRoundStartedAt: nowIso,
    combatSkipEnemyAttack: false,
    combatBossSleepRoundsRemaining: bossProfile(enemy)?.sleepStart ?? null,
    combatBossPendingId: null,
    combatBossPendingHp: null,
    combatBossAddsRemaining: null,
    combatBossAddsTriggered: false,
    combatBossInkActive: false,
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
    combatSkipEnemyAttack: false,
    combatBossSleepRoundsRemaining: null,
    combatBossPendingId: null,
    combatBossPendingHp: null,
    combatBossAddsRemaining: null,
    combatBossAddsTriggered: false,
    combatBossInkActive: false,
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
  const profile = bossProfile(enemy)
  const asleep = (save.combatBossSleepRoundsRemaining ?? 0) > 0
  const fishingMode = profile?.damageMode === 'fishing' && !isBossAddFight(save)
  const enemyMaxHp = enemyEncounterMaxHp(db, save, enemy)

  let bossInkActive = false
  if (
    profile?.inkAt != null &&
    !isBossAddFight(save) &&
    enemyHp <= enemyMaxHp * profile.inkAt &&
    random() < profile.inkChance
  ) {
    bossInkActive = true
  }

  let playerHit: number
  let playerCrit = false
  let offhandHit: number | null = null
  let staffHit: number | null = null

  if (fishingMode) {
    const fishingRange = fishingCombatDamageRange(db, save)
    playerHit = rollDamage(fishingRange.min, fishingRange.max, random)
    if (bossInkActive) playerHit = Math.max(1, Math.floor(playerHit / 2))
    playerHit = applySleepIncoming(playerHit, asleep)
  } else {
    const playerRange = playerDamageRange(db, save)
    playerHit = rollDamage(playerRange.min, playerRange.max, random)
    const critChance = equippedEnchantmentCritChancePercent(db, save)
    if (critChance > 0 && random() * 100 < critChance) {
      playerCrit = true
      playerHit = Math.max(1, Math.floor(playerHit * criticalStrikeDamageMultiplier()))
    }
    if (bossInkActive) playerHit = Math.max(1, Math.floor(playerHit / 2))
    playerHit = applySleepIncoming(playerHit, asleep)
  }

  let nextEnemyHp = Math.max(0, enemyHp - playerHit)

  const weaponId = save.equipment.slots[WEAPON_TOOL_SLOT_ID]?.itemId ?? null

  if (!fishingMode && nextEnemyHp > 0 && weaponId && itemHasCapability(db, weaponId, 'staff_sparks')) {
    const sparks = staffSparksDamageRange(getSkillProgress(save, ARCANA_SKILL_ID).level)
    staffHit = applySleepIncoming(rollDamage(sparks.min, sparks.max, random), asleep)
    nextEnemyHp = Math.max(0, nextEnemyHp - staffHit)
  }

  if (!fishingMode && nextEnemyHp > 0) {
    const offhandRange = playerOffhandDamageRange(db, save)
    if (offhandRange) {
      offhandHit = applySleepIncoming(rollDamage(offhandRange.min, offhandRange.max, random), asleep)
      if (bossInkActive) offhandHit = Math.max(1, Math.floor(offhandHit / 2))
      nextEnemyHp = Math.max(0, nextEnemyHp - offhandHit)
    }
  }

  if (nextEnemyHp > 0) {
    nextEnemyHp = applyPotionEnemyRoundDamage(
      nextEnemyHp,
      enemyMaxHp,
      save.activePotionEffect,
    )
  }

  // Binding procs on this hit: they still attack this round, then skip the next.
  let skipNextEnemyAttack = false
  if (nextEnemyHp > 0 && weaponId && itemHasCapability(db, weaponId, 'staff_binding')) {
    skipNextEnemyAttack = random() < 0.5
  }

  let nextSleep = profile == null ? null : save.combatBossSleepRoundsRemaining ?? 0
  if (nextSleep != null && nextSleep > 0) nextSleep -= 1
  if (profile && nextEnemyHp <= enemyMaxHp * profile.wakeHpRatio) {
    nextSleep = 0
  }

  let bossAddsTriggered = false
  let bossPendingHp: number | null = null
  if (
    profile?.squidlingsAt != null &&
    profile.squidlingEnemyId &&
    !save.combatBossAddsTriggered &&
    !isBossAddFight(save) &&
    nextEnemyHp <= enemyMaxHp * profile.squidlingsAt
  ) {
    bossAddsTriggered = true
    bossPendingHp = nextEnemyHp
  }

  if (nextEnemyHp <= 0 && !bossAddsTriggered) {
    return {
      playerHit,
      playerCrit,
      offhandHit,
      staffHit,
      skipNextEnemyAttack: false,
      enemyHit: null,
      thornsHit: 0,
      bossSleepRoundsRemaining: nextSleep,
      enemyAsleep: asleep,
      enemyRampage: false,
      bossAddsTriggered: false,
      bossInkActive,
      bossPendingHp: null,
      enemyHp: 0,
      playerHp: save.currentHp,
      outcome: 'victory',
    }
  }

  if (bossAddsTriggered) {
    return {
      playerHit,
      playerCrit,
      offhandHit,
      staffHit,
      skipNextEnemyAttack: false,
      enemyHit: null,
      thornsHit: 0,
      bossSleepRoundsRemaining: nextSleep,
      enemyAsleep: asleep,
      enemyRampage: false,
      bossAddsTriggered: true,
      bossInkActive,
      bossPendingHp,
      enemyHp: bossPendingHp ?? nextEnemyHp,
      playerHp: save.currentHp,
      outcome: 'ongoing',
    }
  }

  if (save.combatSkipEnemyAttack || asleep) {
    return {
      playerHit,
      playerCrit,
      offhandHit,
      staffHit,
      skipNextEnemyAttack,
      enemyHit: null,
      thornsHit: 0,
      bossSleepRoundsRemaining: nextSleep,
      enemyAsleep: asleep,
      enemyRampage: false,
      bossAddsTriggered: false,
      bossInkActive,
      bossPendingHp: null,
      enemyHp: nextEnemyHp,
      playerHp: save.currentHp,
      outcome: 'ongoing',
    }
  }

  const rampage = Boolean(profile && nextEnemyHp <= enemyMaxHp * profile.rampageHpRatio)
  const enemyRange = enemyEncounterDamageRange(db, save, enemy)
  let enemyRaw = rollDamage(enemyRange.min, enemyRange.max, random)
  if (rampage) enemyRaw *= 2
  const enemyHit = applyMitigation(enemyRaw, playerDamageReduction(db, save), floor)
  const playerHp = Math.max(0, save.currentHp - enemyHit)

  const thornsPercent = equippedEnchantmentThornsPercent(db, save)
  let thornsHit = thornsPercent > 0 ? Math.round((enemyHit * thornsPercent) / 100) : 0
  thornsHit = applySleepIncoming(thornsHit, asleep)
  if (thornsHit > 0) {
    nextEnemyHp = Math.max(0, nextEnemyHp - thornsHit)
  }

  return {
    playerHit,
    playerCrit,
    offhandHit,
    staffHit,
    skipNextEnemyAttack,
    enemyHit,
    thornsHit,
    bossSleepRoundsRemaining: nextSleep,
    enemyAsleep: asleep,
    enemyRampage: rampage,
    bossAddsTriggered: false,
    bossInkActive,
    bossPendingHp: null,
    enemyHp: nextEnemyHp,
    playerHp,
    // Simultaneous kills favor defeat: the enemy's own hit must land before Thorns reflects it.
    outcome: playerHp <= 0 ? 'defeat' : nextEnemyHp <= 0 ? 'victory' : 'ongoing',
  }
}

/** One-hit kill from full enemy HP with no player damage: skip healing food. */
export function shouldSkipVictoryHealingFood(
  enemy: EnemyRow,
  incomingEnemyHp: number | null | undefined,
  enemyHit: number | null,
  playerHpAfter: number,
  playerHpBefore: number,
  encounterMaxHp?: number,
): boolean {
  const maxHp = encounterMaxHp ?? Number(enemy['Maximum HP'] ?? 0)
  const startedAtFull = incomingEnemyHp == null || incomingEnemyHp === maxHp
  return startedAtFull && enemyHit == null && playerHpAfter === playerHpBefore
}

export function applyCombatVictory(
  db: GameDatabase,
  save: PlayerSave,
  action: ActionRow,
  enemy: EnemyRow,
  random: RandomFn = Math.random,
  nowMs: number = Date.now(),
  options?: { skipVictoryFood?: boolean },
): CombatVictoryResult {
  const maxHp = playerMaxHp(db, save)
  let next: PlayerSave = {
    ...save,
    maxHp,
    currentHp: currentHpAfterMaxChange(save.currentHp, save.maxHp, maxHp),
  }

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
  next = recordEnemyKill(db, next, enemy['Enemy ID'])

  const food = consumeFoodAfterVictory(db, next, { skipHealing: options?.skipVictoryFood })
  next = withBossRespawn(clearCombatSave(food.save), enemy, nowMs)
  next = applyQuestDefeatProgress(db, next, enemy['Enemy ID'], 1)
  next = applyBountyDefeatProgress(next, enemy['Enemy ID'], 1, nowMs)
  next = withoutHeldAction(next, save.currentActivityId)

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
  return withoutHeldAction(
    clearCombatSave(
      revokeCosmetic(
        {
          ...save,
          maxHp,
          currentHp: maxHp,
          deathPauseUntil: new Date(nowMs + pauseSec * 1000).toISOString(),
          hasEverDied: true,
          currentActionId: null,
          actionStartedAt: null,
          actionDurationMs: null,
        },
        STARTER_TITLE_COSMETIC_ID,
      ),
    ),
    save.currentActivityId,
  )
}

export function isDeathPaused(save: PlayerSave, nowMs: number = Date.now()): boolean {
  if (!save.deathPauseUntil) return false
  return Date.parse(save.deathPauseUntil) > nowMs
}

export function deathPauseRemainingMs(save: PlayerSave, nowMs: number = Date.now()): number {
  if (!save.deathPauseUntil) return 0
  return Math.max(0, Date.parse(save.deathPauseUntil) - nowMs)
}
