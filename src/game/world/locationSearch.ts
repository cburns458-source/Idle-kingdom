import { addItemToInventoryExact } from '../activity/rewards'
import type { GameDatabase, LocationSearchRow } from '../data/types'
import type { PlayerSave } from '../save/types'

/** Location Search spots (e.g. "Search around the entrance") available at a Location. */
export function locationSearchesAt(db: GameDatabase, locationId: string): LocationSearchRow[] {
  return db.LocationSearches.filter((row) => row['Location ID'] === locationId)
}

function lastClaimedAtMs(save: PlayerSave, searchId: string): number | null {
  const claimedAt = save.locationSearchClaims?.[searchId]
  if (!claimedAt) return null
  const parsed = Date.parse(claimedAt)
  return Number.isFinite(parsed) ? parsed : null
}

/** Milliseconds remaining before this Search spot can be used again (0 when ready now). */
export function locationSearchCooldownRemainingMs(
  save: PlayerSave,
  search: LocationSearchRow,
  nowMs: number = Date.now(),
): number {
  const lastClaimed = lastClaimedAtMs(save, search['Search ID'])
  if (lastClaimed == null) return 0
  const cooldownMs = Math.max(0, search['Cooldown Hours']) * 60 * 60 * 1000
  return Math.max(0, lastClaimed + cooldownMs - nowMs)
}

export function canClaimLocationSearch(
  save: PlayerSave,
  search: LocationSearchRow,
  nowMs: number = Date.now(),
): boolean {
  return locationSearchCooldownRemainingMs(save, search, nowMs) <= 0
}

export interface LocationSearchClaimResult {
  ok: boolean
  save: PlayerSave
  reason?: string
  itemId?: string
  itemName?: string
  quantity?: number
}

/**
 * Grant the Search reward and stamp the claim. Fails (without mutating the
 * save or consuming the cooldown) if the spot isn't ready yet, or if the
 * inventory has no room — a full bag should not silently waste the search.
 */
export function claimLocationSearch(
  db: GameDatabase,
  save: PlayerSave,
  searchId: string,
  nowMs: number = Date.now(),
): LocationSearchClaimResult {
  const search = db.LocationSearches.find((row) => row['Search ID'] === searchId)
  if (!search) {
    return { ok: false, save, reason: 'Unknown search spot.' }
  }
  if (!canClaimLocationSearch(save, search, nowMs)) {
    return { ok: false, save, reason: 'Already searched here today. Come back later.' }
  }

  const granted = addItemToInventoryExact(save, search['Reward Item ID'], search['Reward Quantity'])
  if (!granted.ok) {
    return { ok: false, save, reason: granted.reason }
  }

  const itemName =
    db.Items.find((item) => item['Item ID'] === search['Reward Item ID'])?.['Display Name'] ??
    search['Reward Item ID']

  return {
    ok: true,
    save: {
      ...granted.save,
      locationSearchClaims: {
        ...granted.save.locationSearchClaims,
        [searchId]: new Date(nowMs).toISOString(),
      },
    },
    itemId: search['Reward Item ID'],
    itemName,
    quantity: search['Reward Quantity'],
  }
}
