import { configNumber } from '../activity/gathering'
import type { RandomFn } from '../activity/pools'
import type { ActionRow, GameDatabase } from '../data/types'
import type { EnemyRow } from '../data/enemyTypes'
import type { PlayerSave } from '../save/types'
import { notePlayerDamaged } from '../vitals/regen'
import {
  MASS_BOSS_ENEMY_ACTIVITY,
  isBossAddFight,
  isMassBossEnemy,
  massHealthMultiplier,
  massHpFor,
  massDropScale,
  massMinimumDamage,
} from './boss'
import { applySquidlingVictory, beginBossAddsEncounter, isSquidlingVictory } from './bossPhase'
import {
  applyCombatDefeat,
  applyCombatVictory,
  beginCombatSave,
  enemyForAction,
  getEnemy,
  openCombatRoundClock,
  resolveCombatRound,
} from './engine'
import { enemyScaledMaxHp } from './stats'
import { bossProfile } from './boss'

export {
  massDropScale,
  massHealthMultiplier,
  massHpFor,
  massMinimumDamage,
} from './boss'

/** Mother squid Notes `player_base_hp_scale` (2.2) is clamped on the RPC too. */
export const MASS_PLAYER_BASE_HP_SCALE_MIN = 0.1
export const MASS_PLAYER_BASE_HP_SCALE_MAX = 10

/**
 * Clamp the caller-supplied squid health scale used by `mass_lock_if_due`.
 *
 * The game edge copies `player_base_hp_scale` from Mother squid Notes (2.2);
 * it is not a Flutter field. The RPC argument is still caller-supplied, so a
 * non-positive or non-finite value is ignored and a finite value is clamped
 * to [0.1, 10] to match the SQL.
 */
export function clampMassPlayerBaseHpScale(scale: number | null | undefined): number | null {
  if (scale == null || !Number.isFinite(scale) || scale <= 0) return null
  return Math.min(MASS_PLAYER_BASE_HP_SCALE_MAX, Math.max(MASS_PLAYER_BASE_HP_SCALE_MIN, scale))
}

export type MassFightTickInput = {
  nowMs: number
  random: RandomFn
  encounterId: string
  enemyId: string
  sharedRemainingHp: number
  healthMultiplier: number
  lockedIn: boolean
  late: boolean
  lastRoundStartedAt: string | null
}

export type MassFightTickResult = {
  save: PlayerSave
  damageDealt: number
  early: boolean
  duplicate: boolean
  started: boolean
  kill: boolean
  defeated: boolean
  roundStartedAt: string | null
}

function actionForBoss(db: GameDatabase, enemyId: string): ActionRow | undefined {
  const activityId = MASS_BOSS_ENEMY_ACTIVITY[enemyId]
  if (!activityId) return undefined
  return db.Actions.find((row) => {
    if (row.Category !== 'Combat') return false
    return row['Target ID'] === enemyId
  })
}

export function massSoloBaseHp(
  _db: GameDatabase,
  enemy: EnemyRow,
  playerBaseHpValues: number[],
): number {
  const profile = bossProfile(enemy)
  if (profile?.playerBaseHpScale != null) {
    const n = Math.max(1, playerBaseHpValues.length)
    const sum = playerBaseHpValues.reduce((total, value) => total + Math.max(0, value), 0)
    const avg = sum / n
    return Math.max(1, Math.floor(avg * profile.playerBaseHpScale))
  }
  return enemyScaledMaxHp(enemy)
}

export function massEncounterHp(
  db: GameDatabase,
  enemy: EnemyRow,
  lockedCount: number,
  playerBaseHpValues: number[],
): {
  soloHp: number
  healthMultiplier: number
  totalHp: number
  dropScale: number
  minDamage: number
} {
  const n = Math.max(1, Math.floor(lockedCount))
  const soloHp = massSoloBaseHp(db, enemy, playerBaseHpValues)
  const healthMultiplier = massHealthMultiplier(n)
  const totalHp = massHpFor(soloHp, n)
  return {
    soloHp,
    healthMultiplier,
    totalHp,
    dropScale: massDropScale(n),
    minDamage: massMinimumDamage(totalHp, n),
  }
}

function roundEndMs(db: GameDatabase, save: PlayerSave): number | null {
  if (!save.combatRoundStartedAt) return null
  const roundStart = Date.parse(save.combatRoundStartedAt)
  if (!Number.isFinite(roundStart)) return null
  const roundMs = Math.max(1, configNumber(db, 'combat_round_duration', 6) * 1000)
  return roundStart + roundMs
}

/**
 * One server-authoritative mass combat tick. Early or duplicate clocks add
 * no damage. Late joiners still fight locally but do not change shared HP.
 */
export function simulateMassFightTick(
  db: GameDatabase,
  save: PlayerSave,
  input: MassFightTickInput,
): MassFightTickResult {
  const empty: MassFightTickResult = {
    save,
    damageDealt: 0,
    early: false,
    duplicate: false,
    started: false,
    kill: false,
    defeated: false,
    roundStartedAt: save.combatRoundStartedAt,
  }
  if (!isMassBossEnemy(input.enemyId)) return empty
  const enemy = getEnemy(db, input.enemyId)
  const action = actionForBoss(db, input.enemyId) ?? (save.currentActionId
    ? db.Actions.find((row) => row['Action ID'] === save.currentActionId)
    : undefined)
  if (!enemy || !action) return empty

  const nowIso = new Date(input.nowMs).toISOString()
  let next = save.massEncounterId === input.encounterId ? save : { ...save, massEncounterId: input.encounterId }

  if (
    !next.combatEnemyId ||
    (next.combatEnemyId !== input.enemyId &&
      next.combatBossPendingId !== input.enemyId &&
      !isBossAddFight(next))
  ) {
    next = {
      ...beginCombatSave(db, next, action, enemy, nowIso, input.sharedRemainingHp),
      massEncounterId: input.encounterId,
    }
    return {
      save: next,
      damageDealt: 0,
      early: false,
      duplicate: false,
      started: true,
      kill: false,
      defeated: false,
      roundStartedAt: next.combatRoundStartedAt,
    }
  }

  const due = roundEndMs(db, next)
  if (due == null || input.nowMs < due) {
    return { ...empty, save: next, early: true, roundStartedAt: next.combatRoundStartedAt }
  }
  if (input.lastRoundStartedAt && input.lastRoundStartedAt === next.combatRoundStartedAt) {
    return { ...empty, save: next, duplicate: true, roundStartedAt: next.combatRoundStartedAt }
  }

  const fightingAdds = isBossAddFight(next)
  const combatEnemy = getEnemy(db, next.combatEnemyId ?? input.enemyId) ?? enemy
  const hpForRound = fightingAdds ? (next.combatEnemyHp ?? 0) : input.sharedRemainingHp
  const roundStartedAt = next.combatRoundStartedAt
  const round = resolveCombatRound(db, next, combatEnemy, hpForRound, input.random)

  let damageDealt = 0
  if (!fightingAdds && input.lockedIn && !input.late) {
    damageDealt = Math.max(0, input.sharedRemainingHp - round.enemyHp)
  }
  const sharedAfter = Math.max(0, input.sharedRemainingHp - damageDealt)

  if (round.lifestealHealed > 0) {
    // Lifesteal is already in round.playerHp.
  }

  let after: PlayerSave = {
    ...next,
    combatEnemyHp: fightingAdds ? round.enemyHp : sharedAfter,
    currentHp: round.playerHp,
    combatPlayerSwingApplied: true,
    combatPendingRound: round,
    combatBossInkActive: round.bossInkActive,
    massEncounterId: input.encounterId,
  }
  if ((round.enemyHit ?? 0) > 0) {
    after = notePlayerDamaged(after, due)
  }

  if (round.outcome === 'defeat') {
    return {
      save: applyCombatDefeat(db, { ...after, currentHp: 0 }, due),
      damageDealt,
      early: false,
      duplicate: false,
      started: false,
      kill: false,
      defeated: true,
      roundStartedAt,
    }
  }

  if (round.outcome === 'victory' && isSquidlingVictory(after, combatEnemy)) {
    const squidling = applySquidlingVictory(
      db,
      { ...after, combatEnemyHp: 0, currentHp: round.playerHp },
      combatEnemy,
      new Date(due).toISOString(),
      input.healthMultiplier,
    )
    let resumed = squidling.save
    if (squidling.bossResumed) {
      resumed = { ...resumed, combatEnemyHp: sharedAfter, massEncounterId: input.encounterId }
    } else {
      resumed = { ...resumed, massEncounterId: input.encounterId }
    }
    return {
      save: resumed,
      damageDealt: 0,
      early: false,
      duplicate: false,
      started: false,
      kill: false,
      defeated: false,
      roundStartedAt,
    }
  }

  if (round.bossAddsTriggered && round.bossPendingHp != null) {
    const profile = bossProfile(enemy)
    if (profile?.squidlingEnemyId) {
      const addsStarted = beginBossAddsEncounter(
        db,
        {
          ...after,
          currentHp: round.playerHp,
          combatBossInkActive: round.bossInkActive,
        },
        enemy,
        profile,
        sharedAfter,
        new Date(due).toISOString(),
        input.healthMultiplier,
      )
      return {
        save: { ...addsStarted, massEncounterId: input.encounterId },
        damageDealt,
        early: false,
        duplicate: false,
        started: false,
        kill: sharedAfter <= 0,
        defeated: false,
        roundStartedAt,
      }
    }
  }

  if (round.outcome === 'victory' && !fightingAdds) {
    return {
      save: {
        ...after,
        combatEnemyHp: 0,
        massEncounterId: input.encounterId,
      },
      damageDealt,
      early: false,
      duplicate: false,
      started: false,
      kill: sharedAfter <= 0,
      defeated: false,
      roundStartedAt,
    }
  }

  return {
    save: {
      ...after,
      combatSkipEnemyAttack: round.skipNextEnemyAttack,
      combatBossSleepRoundsRemaining: round.bossSleepRoundsRemaining,
      combatBossInkActive: round.bossInkActive,
      ...openCombatRoundClock(db, due),
      massEncounterId: input.encounterId,
    },
    damageDealt,
    early: false,
    duplicate: false,
    started: false,
    kill: sharedAfter <= 0,
    defeated: false,
    roundStartedAt,
  }
}

export function applyMassVictory(
  db: GameDatabase,
  save: PlayerSave,
  enemy: EnemyRow,
  random: RandomFn,
  nowMs: number,
  dropScale: number,
): ReturnType<typeof applyCombatVictory> {
  const action =
    actionForBoss(db, enemy['Enemy ID']) ??
    (save.currentActionId
      ? db.Actions.find((row) => row['Action ID'] === save.currentActionId)
      : undefined)
  if (!action) {
    return applyCombatVictory(db, save, db.Actions[0]!, enemy, random, nowMs, false, 0)
  }
  return applyCombatVictory(db, save, action, enemy, random, nowMs, false, dropScale)
}

export function massActivityIdForEnemy(enemyId: string): string | null {
  return MASS_BOSS_ENEMY_ACTIVITY[enemyId] ?? null
}

export type MassParticipantView = {
  userId: string
  username: string
  late: boolean
  lockedIn: boolean
  present: boolean
  damageDealt: number
}

export type MassYouView = {
  late: boolean
  lockedIn: boolean
  present: boolean
  damageDealt: number
  payoutEligible: boolean | null
  payoutClaimed: boolean
  lastRoundStartedAt: string | null
}

export type MassEncounterStatus = 'lobby' | 'fighting' | 'settled' | 'closed'

export type MassEncounterSnapshot = {
  encounterId: string
  enemyId: string
  status: MassEncounterStatus
  countdownEndsAt: string | null
  spawnedAt: string | null
  lockedCount: number
  soloHp: number
  healthMultiplier: number
  totalHp: number
  remainingHp: number
  dropScale: number
  minDamage: number
  lastLockedTickAt: string | null
  closeReason: string | null
  participants: MassParticipantView[]
  you: MassYouView | null
  damageAdded?: number
  duplicate?: boolean
  alreadySettled?: boolean
  closed?: boolean
  eligible?: boolean
  alreadyClaimed?: boolean
}

function asFiniteNumber(value: unknown, fallback = 0): number {
  if (typeof value === 'number' && Number.isFinite(value)) return value
  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value)
    if (Number.isFinite(parsed)) return parsed
  }
  return fallback
}

function asIso(value: unknown): string | null {
  if (typeof value !== 'string' || value.length === 0) return null
  return value
}

function parseParticipant(raw: unknown): MassParticipantView | null {
  if (!raw || typeof raw !== 'object') return null
  const row = raw as Record<string, unknown>
  const userId = typeof row.userId === 'string' ? row.userId : null
  if (!userId) return null
  return {
    userId,
    username: typeof row.username === 'string' && row.username.length > 0 ? row.username : 'Adventurer',
    late: row.late === true,
    lockedIn: row.lockedIn === true,
    present: row.present === true,
    damageDealt: asFiniteNumber(row.damageDealt),
  }
}

export function parseMassSnapshot(raw: unknown): MassEncounterSnapshot | null {
  if (!raw || typeof raw !== 'object') return null
  const row = raw as Record<string, unknown>
  if (row.ok === false) return null
  const encounterId = typeof row.encounterId === 'string' ? row.encounterId : null
  const enemyId = typeof row.enemyId === 'string' ? row.enemyId : null
  const status = row.status
  if (!encounterId || !enemyId) return null
  if (status !== 'lobby' && status !== 'fighting' && status !== 'settled' && status !== 'closed') {
    return null
  }
  const youRaw = row.you
  let you: MassYouView | null = null
  if (youRaw && typeof youRaw === 'object') {
    const y = youRaw as Record<string, unknown>
    you = {
      late: y.late === true,
      lockedIn: y.lockedIn === true,
      present: y.present === true,
      damageDealt: asFiniteNumber(y.damageDealt),
      payoutEligible: typeof y.payoutEligible === 'boolean' ? y.payoutEligible : null,
      payoutClaimed: y.payoutClaimed === true,
      lastRoundStartedAt: asIso(y.lastRoundStartedAt),
    }
  }
  const participants = Array.isArray(row.participants)
    ? row.participants.map(parseParticipant).filter((row): row is MassParticipantView => row != null)
    : []
  return {
    encounterId,
    enemyId,
    status,
    countdownEndsAt: asIso(row.countdownEndsAt),
    spawnedAt: asIso(row.spawnedAt),
    lockedCount: Math.max(0, Math.floor(asFiniteNumber(row.lockedCount))),
    soloHp: asFiniteNumber(row.soloHp),
    healthMultiplier: asFiniteNumber(row.healthMultiplier, 1),
    totalHp: asFiniteNumber(row.totalHp),
    remainingHp: asFiniteNumber(row.remainingHp),
    dropScale: asFiniteNumber(row.dropScale, 1),
    minDamage: asFiniteNumber(row.minDamage),
    lastLockedTickAt: asIso(row.lastLockedTickAt),
    closeReason: typeof row.closeReason === 'string' ? row.closeReason : null,
    participants,
    you,
    damageAdded: typeof row.damageAdded === 'number' ? row.damageAdded : undefined,
    duplicate: typeof row.duplicate === 'boolean' ? row.duplicate : undefined,
    alreadySettled: typeof row.alreadySettled === 'boolean' ? row.alreadySettled : undefined,
    closed: row.closed === true ? true : undefined,
    eligible: typeof row.eligible === 'boolean' ? row.eligible : undefined,
    alreadyClaimed: typeof row.alreadyClaimed === 'boolean' ? row.alreadyClaimed : undefined,
  }
}

export function massEnemyForAction(db: GameDatabase, action: ActionRow): EnemyRow | undefined {
  return enemyForAction(db, action)
}
