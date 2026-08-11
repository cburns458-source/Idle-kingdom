import { withRecalculatedVitals } from '../equipment/vitals'
import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import { grantRaceStartingItems, raceById } from './races'

export type AssignRaceResult =
  | { ok: true; save: PlayerSave; grantedStarterKit: boolean }
  | { ok: false; reason: string }

/**
 * Set the player's race. When moving from no race → a race (first pick),
 * grants that race's starting item kit. Later race changes (menu test /
 * future quest) only swap raceId and refresh vitals — kits are not re-granted.
 */
export function assignRace(
  db: GameDatabase,
  save: PlayerSave,
  raceId: string,
): AssignRaceResult {
  const race = raceById(db, raceId)
  if (!race) return { ok: false, reason: 'Unknown race.' }

  const firstSelection = save.raceId == null
  let next: PlayerSave = { ...save, raceId }
  if (firstSelection) {
    next = grantRaceStartingItems(db, next, raceId)
  }
  next = withRecalculatedVitals(db, next)
  return { ok: true, save: next, grantedStarterKit: firstSelection }
}
