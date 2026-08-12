import { syncProgressionMeta } from '../achievements/progress'
import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import { stampUnattendedProgressAt } from '../unattended/resolve'

/**
 * Everything that happens to a save on its way to storage.
 *
 * Every write goes through here so two things can never be forgotten: the
 * unattended anchor moves to now (otherwise the next load would replay time the
 * player was present for), and achievements and statistics catch up with
 * whatever the save just did.
 */
export function prepareSaveForWrite(
  db: GameDatabase,
  save: PlayerSave,
  nowMs: number = Date.now(),
): PlayerSave {
  return syncProgressionMeta(db, stampUnattendedProgressAt(save, nowMs))
}
