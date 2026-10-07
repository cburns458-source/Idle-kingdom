import { overlayPvpLiveStats, stripPvpConsumables } from '../combat/pvp'
import { combatLevelOf } from '../combat/stats'
import type { GameDatabase } from '../data/types'
import { leaderboardRowsFor, remoteUsername } from '../multiplayer/remote'
import { buildLeaderboardSnapshot } from '../multiplayer/snapshots'
import { publicEquipmentFromSave } from '../multiplayer/types'
import { parseSave } from '../save/saveStore'
import { PET_COSMETIC_SLOT_ID, type PlayerSave } from '../save/types'
import { totalLevel } from '../skills/totals'

export type RankingBoardRow = {
  user_id: string
  board_key: string
  value: number
  value_secondary: number
  updated_at: string
}

export type PvpSnapshotRow = {
  user_id: string
  username: string
  combat_level: number
  total_level: number
  appearance_json: Record<string, unknown>
  payload: PlayerSave
  updated_at: string
}

function appearanceJsonForSave(save: PlayerSave): Record<string, unknown> {
  return {
    ...save.appearance,
    ...(save.raceId ? { raceId: save.raceId } : {}),
  }
}

/** Leaderboard rows derived from the hosted save. A client cannot invent these. */
export function rankingBoardRowsFor(
  db: GameDatabase,
  save: PlayerSave,
  userId: string,
  nowIso: string,
): RankingBoardRow[] {
  return leaderboardRowsFor(userId, buildLeaderboardSnapshot(db, save), nowIso).map((row) => ({
    user_id: String(row.user_id ?? userId),
    board_key: String(row.board_key ?? ''),
    value: Number(row.value ?? 0),
    value_secondary: Number(row.value_secondary ?? 0),
    updated_at: String(row.updated_at ?? nowIso),
  }))
}

/** Public gear, motto, and pet taken from the hosted save. */
export function rankingProfilePatch(save: PlayerSave): {
  equipment_json: ReturnType<typeof publicEquipmentFromSave>
  motto: string | null
  pet_cosmetic_id: string | null
  appearance_json: Record<string, unknown>
} {
  return {
    equipment_json: publicEquipmentFromSave(save),
    motto: save.motto ?? null,
    pet_cosmetic_id: save.cosmetics.equipped[PET_COSMETIC_SLOT_ID] ?? null,
    appearance_json: appearanceJsonForSave(save),
  }
}

/** Redacted PvP loadout published by Save equipment. */
export function pvpSnapshotRowForSave(options: {
  userId: string
  username: string
  save: PlayerSave
  nowIso: string
}): PvpSnapshotRow {
  const loadout = stripPvpConsumables(options.save)
  const fromSave = loadout.characterName ?? ''
  const username = remoteUsername(options.username || fromSave || options.userId) || 'Adventurer'
  return {
    user_id: options.userId,
    username: username.length > 0 ? username : 'Adventurer',
    combat_level: combatLevelOf(loadout),
    total_level: totalLevel(loadout),
    appearance_json: appearanceJsonForSave(loadout),
    payload: loadout,
    updated_at: options.nowIso,
  }
}

/** Copies live combat stats onto an already-published loadout. */
export function overlayPublishedPvpSnapshot(
  existingPayload: unknown,
  live: PlayerSave,
  nowMs: number,
): PlayerSave | null {
  if (existingPayload == null) return null
  try {
    return overlayPvpLiveStats(parseSave(existingPayload, nowMs), live)
  } catch {
    return null
  }
}
