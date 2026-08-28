import { configString } from '../activity/gathering'
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

export const BLESSING_OVERHEAL_RATIO = 0.1

/** Blessing always snaps to 110% of current max. Extra 10% does not stack. */
export function blessedCurrentHp(maxHp: number): number {
  return maxHp + Math.floor(maxHp * BLESSING_OVERHEAL_RATIO)
}

function blessingMessage(db: GameDatabase, alreadyBlessed: boolean): string {
  return alreadyBlessed
    ? configString(db, 'copy.amenity.blessing.already_full', "The monks' blessing already fills you.")
    : configString(db, 'copy.amenity.blessing.restored', 'The monks restore you beyond full health.')
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
    return {
      ok: false,
      alreadyFull: false,
      reason: configString(db, 'copy.amenity.blessing.not_here', 'The monks are not here.'),
    }
  }

  const next = withRecalculatedVitals(db, save)
  const targetHp = blessedCurrentHp(next.maxHp)
  const alreadyBlessed = next.currentHp >= targetHp
  return {
    ok: true,
    save: { ...next, currentHp: targetHp },
    alreadyFull: alreadyBlessed,
    message: blessingMessage(db, alreadyBlessed),
  }
}
