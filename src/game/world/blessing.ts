import type { GameDatabase, LocationRow } from '../data/types'
import { isDeathPaused } from '../combat/engine'
import { withRecalculatedVitals } from '../equipment/vitals'
import type { PlayerSave } from '../save/types'

export const TEMPLE_LOCATION_ID = 'LOC-0036'

export function locationHasBlessing(location: LocationRow | undefined | null): boolean {
  return location?.['Internal Key'] === 'temple'
}

export type BlessResult =
  | { ok: true; save: PlayerSave; alreadyFull: boolean; message: string; reason?: undefined }
  | { ok: false; save?: undefined; alreadyFull: false; message?: undefined; reason: string }

function blessingMessage(alreadyFull: boolean): string {
  return alreadyFull ? 'You are already at full health.' : 'The monks restore you to full health.'
}

/** Instant Temple heal. Does not start an activity or change equipment. */
export function requestBlessing(db: GameDatabase, save: PlayerSave, nowMs: number): BlessResult {
  if (isDeathPaused(save, nowMs)) {
    return {
      ok: false,
      alreadyFull: false,
      reason: 'Cannot receive a blessing while recovering from defeat.',
    }
  }
  const location = db.Locations.find((row) => row['Location ID'] === save.currentLocationId)
  if (!locationHasBlessing(location)) {
    return { ok: false, alreadyFull: false, reason: 'The monks are not here.' }
  }

  const next = withRecalculatedVitals(db, save)
  if (next.currentHp >= next.maxHp) {
    return { ok: true, save: next, alreadyFull: true, message: blessingMessage(true) }
  }
  return {
    ok: true,
    save: { ...next, currentHp: next.maxHp },
    alreadyFull: false,
    message: blessingMessage(false),
  }
}
