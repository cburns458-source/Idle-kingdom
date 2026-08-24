import type { EnemyRow } from '../data/enemyTypes'
import type { PlayerSave } from '../save/types'

export const DEFAULT_BOSS_SLEEP_ROUNDS = 4
export const DEFAULT_BOSS_WAKE_HP_RATIO = 0.5
export const DEFAULT_BOSS_RAMPAGE_HP_RATIO = 0.25
export const DEFAULT_BOSS_RESPAWN_SECONDS = 10

export interface BossProfile {
  sleepStart: number
  wakeHpRatio: number
  rampageHpRatio: number
  respawnSeconds: number
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

export function isBossEnemy(enemy: EnemyRow | null | undefined): boolean {
  if (!enemy) return false
  return noteTokens(enemy.Notes).some((token) => token.toLowerCase() === 'boss')
}

export function bossProfile(enemy: EnemyRow | null | undefined): BossProfile | null {
  if (!isBossEnemy(enemy)) return null
  const tokens = noteTokens(enemy!.Notes)
  return {
    sleepStart: Math.max(0, Math.floor(noteNumber(tokens, 'sleep_start', DEFAULT_BOSS_SLEEP_ROUNDS))),
    wakeHpRatio: noteNumber(tokens, 'wake_hp_ratio', DEFAULT_BOSS_WAKE_HP_RATIO),
    rampageHpRatio: noteNumber(tokens, 'rampage_hp_ratio', DEFAULT_BOSS_RAMPAGE_HP_RATIO),
    respawnSeconds: Math.max(
      0,
      noteNumber(tokens, 'respawn_seconds', DEFAULT_BOSS_RESPAWN_SECONDS),
    ),
  }
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
