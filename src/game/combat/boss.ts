import type { EnemyRow } from '../data/enemyTypes'
import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import { playerBaseMaxHp } from './stats'

export const DEFAULT_BOSS_SLEEP_ROUNDS = 4
export const DEFAULT_BOSS_WAKE_HP_RATIO = 0.5
export const DEFAULT_BOSS_RAMPAGE_HP_RATIO = 0.25
export const DEFAULT_BOSS_RESPAWN_SECONDS = 10
export const DEFAULT_BOSS_INK_CHANCE = 0.35
export const DEFAULT_BOSS_SQUIDLING_COUNT = 3

export type BossDamageMode = 'fishing'

export interface BossProfile {
  sleepStart: number
  wakeHpRatio: number
  rampageHpRatio: number
  respawnSeconds: number
  squidlingsAt: number | null
  squidlingEnemyId: string | null
  squidlingCount: number
  inkAt: number | null
  inkChance: number
  damageMode: BossDamageMode | null
  /** When set, encounter max HP = playerBaseMaxHp × this scale (armor HP ignored). */
  playerBaseHpScale: number | null
  /** When both pct fields are set, enemy damage is this % of playerBaseMaxHp. */
  playerBaseDamagePctMin: number | null
  playerBaseDamagePctMax: number | null
}

function noteTokens(notes: string | null | undefined): string[] {
  return String(notes ?? '')
    .split(';')
    .map((token) => token.trim())
    .filter((token) => token.length > 0)
}

function noteNumber(tokens: string[], key: string, fallback: number): number {
  const prefix = `${key}:`
  for (const token of tokens) {
    if (!token.toLowerCase().startsWith(prefix)) continue
    const parsed = Number(token.slice(prefix.length).trim())
    if (Number.isFinite(parsed)) return parsed
  }
  return fallback
}

function noteString(tokens: string[], key: string, fallback: string | null = null): string | null {
  const prefix = `${key}:`
  for (const token of tokens) {
    if (!token.toLowerCase().startsWith(prefix)) continue
    const value = token.slice(prefix.length).trim()
    if (value.length > 0) return value
  }
  return fallback
}

export function isBossEnemy(enemy: EnemyRow | null | undefined): boolean {
  if (!enemy) return false
  return noteTokens(enemy.Notes).some((token) => token.toLowerCase() === 'boss')
}

export function bossProfile(enemy: EnemyRow | null | undefined): BossProfile | null {
  if (!isBossEnemy(enemy)) return null
  const tokens = noteTokens(enemy!.Notes)
  const squidlingsAtRaw = noteNumber(tokens, 'squidlings_at', Number.NaN)
  const inkAtRaw = noteNumber(tokens, 'ink_at', Number.NaN)
  const hpScaleRaw = noteNumber(tokens, 'player_base_hp_scale', Number.NaN)
  const dmgMinRaw = noteNumber(tokens, 'player_base_damage_pct_min', Number.NaN)
  const dmgMaxRaw = noteNumber(tokens, 'player_base_damage_pct_max', Number.NaN)
  const damageModeRaw = noteString(tokens, 'damage_mode', null)?.toLowerCase() ?? null
  return {
    sleepStart: Math.max(0, Math.floor(noteNumber(tokens, 'sleep_start', DEFAULT_BOSS_SLEEP_ROUNDS))),
    wakeHpRatio: noteNumber(tokens, 'wake_hp_ratio', DEFAULT_BOSS_WAKE_HP_RATIO),
    rampageHpRatio: noteNumber(tokens, 'rampage_hp_ratio', DEFAULT_BOSS_RAMPAGE_HP_RATIO),
    respawnSeconds: Math.max(
      0,
      noteNumber(tokens, 'respawn_seconds', DEFAULT_BOSS_RESPAWN_SECONDS),
    ),
    squidlingsAt: Number.isFinite(squidlingsAtRaw) ? squidlingsAtRaw : null,
    squidlingEnemyId: noteString(tokens, 'squidling_enemy', null),
    squidlingCount: Math.max(
      1,
      Math.floor(noteNumber(tokens, 'squidling_count', DEFAULT_BOSS_SQUIDLING_COUNT)),
    ),
    inkAt: Number.isFinite(inkAtRaw) ? inkAtRaw : null,
    inkChance: noteNumber(tokens, 'ink_chance', DEFAULT_BOSS_INK_CHANCE),
    damageMode: damageModeRaw === 'fishing' ? 'fishing' : null,
    playerBaseHpScale: Number.isFinite(hpScaleRaw) ? hpScaleRaw : null,
    playerBaseDamagePctMin: Number.isFinite(dmgMinRaw) ? dmgMinRaw : null,
    playerBaseDamagePctMax: Number.isFinite(dmgMaxRaw) ? dmgMaxRaw : null,
  }
}

/** Encounter max HP: scaled from player base HP when the boss profile asks for it. */
export function enemyEncounterMaxHp(
  db: GameDatabase,
  save: PlayerSave,
  enemy: EnemyRow,
): number {
  const profile = bossProfile(enemy)
  if (profile?.playerBaseHpScale != null) {
    return Math.max(1, Math.floor(playerBaseMaxHp(db, save) * profile.playerBaseHpScale))
  }
  return enemy['Maximum HP']
}

/** Read player-base damage % notes from any enemy (boss or add). */
function playerBaseDamagePctFromNotes(
  enemy: EnemyRow,
): { min: number; max: number } | null {
  const profile = bossProfile(enemy)
  if (profile?.playerBaseDamagePctMin != null && profile.playerBaseDamagePctMax != null) {
    return { min: profile.playerBaseDamagePctMin, max: profile.playerBaseDamagePctMax }
  }
  const tokens = noteTokens(enemy.Notes)
  const dmgMinRaw = noteNumber(tokens, 'player_base_damage_pct_min', Number.NaN)
  const dmgMaxRaw = noteNumber(tokens, 'player_base_damage_pct_max', Number.NaN)
  if (!Number.isFinite(dmgMinRaw) || !Number.isFinite(dmgMaxRaw)) return null
  return { min: dmgMinRaw, max: dmgMaxRaw }
}

/** Enemy damage range for this encounter (scaled or static Min/Max Damage). */
export function enemyEncounterDamageRange(
  db: GameDatabase,
  save: PlayerSave,
  enemy: EnemyRow,
): { min: number; max: number } {
  const pct = playerBaseDamagePctFromNotes(enemy)
  if (pct) {
    const base = playerBaseMaxHp(db, save)
    const min = Math.max(1, Math.floor((base * pct.min) / 100))
    const max = Math.max(min, Math.floor((base * pct.max) / 100))
    return { min, max }
  }
  return { min: enemy['Min Damage'], max: enemy['Max Damage'] }
}

export function isBossAddFight(save: PlayerSave): boolean {
  return (
    save.combatBossPendingId != null &&
    save.combatBossAddsRemaining != null &&
    save.combatBossAddsRemaining > 0
  )
}

export function bossRespawnUntilMs(save: PlayerSave, enemyId: string): number | null {
  const iso = save.bossRespawnUntilByEnemyId[enemyId]
  if (!iso) return null
  const ms = Date.parse(iso)
  return Number.isFinite(ms) ? ms : null
}

export function isBossRespawnReady(save: PlayerSave, enemyId: string, nowMs: number): boolean {
  const until = bossRespawnUntilMs(save, enemyId)
  return until == null || nowMs >= until
}

export function withBossRespawn(
  save: PlayerSave,
  enemy: EnemyRow,
  nowMs: number,
): PlayerSave {
  const profile = bossProfile(enemy)
  if (!profile) return save
  return {
    ...save,
    bossRespawnUntilByEnemyId: {
      ...save.bossRespawnUntilByEnemyId,
      [enemy['Enemy ID']]: new Date(nowMs + profile.respawnSeconds * 1000).toISOString(),
    },
  }
}

export function applySleepIncoming(damage: number, asleep: boolean): number {
  if (!asleep) return damage
  return Math.floor(damage / 2)
}
