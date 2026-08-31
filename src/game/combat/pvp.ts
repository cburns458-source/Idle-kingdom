import { configNumber } from '../activity/gathering'
import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import {
  criticalStrikeDamageMultiplier,
  equippedEnchantmentCritChancePercent,
  equippedEnchantmentThornsPercent,
} from '../projects/enchantments'
import {
  applyMitigation,
  playerDamageRange,
  playerDamageReduction,
  playerMaxHp,
  playerOffhandDamageRange,
  rollDamage,
} from './stats'

export type RandomFn = () => number

export interface PvpRoundResult {
  youHit: number
  youCrit: boolean
  youOffhand: number | null
  themHit: number | null
  themCrit: boolean
  themOffhand: number | null
  youThorns: number
  themThorns: number
  youHp: number
  themHp: number
  outcome: 'ongoing' | 'win' | 'loss'
}

export interface PvpFightResult {
  rounds: PvpRoundResult[]
  outcome: 'win' | 'loss'
  youMaxHp: number
  themMaxHp: number
}

interface StrikeResult {
  hit: number
  crit: boolean
  offhand: number | null
  hp: number
  dealt: number
}

const MAX_PVP_ROUNDS = 2000

function strike(
  db: GameDatabase,
  attacker: PlayerSave,
  defenderHp: number,
  defenderDr: number,
  floor: number,
  random: RandomFn,
): StrikeResult {
  const range = playerDamageRange(db, attacker)
  let hit = rollDamage(range.min, range.max, random)
  let crit = false
  const critChance = equippedEnchantmentCritChancePercent(db, attacker)
  if (critChance > 0 && random() * 100 < critChance) {
    crit = true
    hit = Math.max(1, Math.floor(hit * criticalStrikeDamageMultiplier()))
  }
  hit = applyMitigation(hit, defenderDr, floor)
  let hp = Math.max(0, defenderHp - hit)
  let offhand: number | null = null
  if (hp > 0) {
    const offhandRange = playerOffhandDamageRange(db, attacker)
    if (offhandRange) {
      offhand = applyMitigation(
        rollDamage(offhandRange.min, offhandRange.max, random),
        defenderDr,
        floor,
      )
      hp = Math.max(0, hp - offhand)
    }
  }
  return { hit, crit, offhand, hp, dealt: hit + (offhand ?? 0) }
}

function thornsFrom(dealt: number, percent: number): number {
  if (percent <= 0 || dealt <= 0) return 0
  return Math.round((dealt * percent) / 100)
}

/** Why a fight is refused when the player has not published a loadout. */
export const pvpEquipmentRequired = 'Save equipment first.'

/** Keeps snapshot gear and copies live combat, race, and look onto it. */
export function overlayPvpLiveStats(snapshot: PlayerSave, live: PlayerSave): PlayerSave {
  return {
    ...snapshot,
    skills: live.skills,
    raceId: live.raceId,
    appearance: live.appearance,
    characterName: live.characterName,
  }
}

/** Saved loadout plus the live character: gear from [loadout], combat and race from [live]. */
export function composePvpFighter(db: GameDatabase, live: PlayerSave, loadout: PlayerSave): PlayerSave {
  return preparePvpFighter(db, { ...live, equipment: loadout.equipment })
}

/** Snapshot PvP: the given save, at full HP, with potions stripped. */
export function preparePvpFighter(db: GameDatabase, save: PlayerSave): PlayerSave {
  const maxHp = playerMaxHp(db, save)
  return {
    ...save,
    maxHp,
    currentHp: maxHp,
    activePotionEffect: null,
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
  }
}

export function resolvePvpRound(
  db: GameDatabase,
  you: PlayerSave,
  them: PlayerSave,
  youHp: number,
  themHp: number,
  random: RandomFn = Math.random,
): PvpRoundResult {
  const floor = configNumber(db, 'damage_floor', 1)
  const youDr = playerDamageReduction(db, you)
  const themDr = playerDamageReduction(db, them)

  const yourSwing = strike(db, you, themHp, themDr, floor, random)
  let nextThemHp = yourSwing.hp
  const themThorns = thornsFrom(yourSwing.dealt, equippedEnchantmentThornsPercent(db, them))
  let nextYouHp = Math.max(0, youHp - themThorns)

  if (nextYouHp <= 0) {
    return {
      youHit: yourSwing.hit,
      youCrit: yourSwing.crit,
      youOffhand: yourSwing.offhand,
      themHit: null,
      themCrit: false,
      themOffhand: null,
      youThorns: 0,
      themThorns,
      youHp: 0,
      themHp: nextThemHp,
      outcome: 'loss',
    }
  }
  if (nextThemHp <= 0) {
    return {
      youHit: yourSwing.hit,
      youCrit: yourSwing.crit,
      youOffhand: yourSwing.offhand,
      themHit: null,
      themCrit: false,
      themOffhand: null,
      youThorns: 0,
      themThorns,
      youHp: nextYouHp,
      themHp: 0,
      outcome: 'win',
    }
  }

  const theirSwing = strike(db, them, nextYouHp, youDr, floor, random)
  nextYouHp = theirSwing.hp
  const youThorns = thornsFrom(theirSwing.dealt, equippedEnchantmentThornsPercent(db, you))
  if (youThorns > 0) {
    nextThemHp = Math.max(0, nextThemHp - youThorns)
  }

  return {
    youHit: yourSwing.hit,
    youCrit: yourSwing.crit,
    youOffhand: yourSwing.offhand,
    themHit: theirSwing.hit,
    themCrit: theirSwing.crit,
    themOffhand: theirSwing.offhand,
    youThorns,
    themThorns,
    youHp: nextYouHp,
    themHp: nextThemHp,
    outcome: nextYouHp <= 0 ? 'loss' : nextThemHp <= 0 ? 'win' : 'ongoing',
  }
}

export function simulatePvpFight(
  db: GameDatabase,
  youSave: PlayerSave,
  themSave: PlayerSave,
  random: RandomFn = Math.random,
): PvpFightResult {
  const you = preparePvpFighter(db, youSave)
  const them = preparePvpFighter(db, themSave)
  const youMaxHp = you.currentHp
  const themMaxHp = them.currentHp
  const rounds: PvpRoundResult[] = []
  let youHp = youMaxHp
  let themHp = themMaxHp
  let outcome: 'win' | 'loss' = 'loss'

  for (let i = 0; i < MAX_PVP_ROUNDS; i++) {
    const round = resolvePvpRound(db, you, them, youHp, themHp, random)
    rounds.push(round)
    youHp = round.youHp
    themHp = round.themHp
    if (round.outcome !== 'ongoing') {
      outcome = round.outcome
      break
    }
  }

  return { rounds, outcome, youMaxHp, themMaxHp }
}
