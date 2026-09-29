import type { ActivityRow, GameDatabase } from '../data/types'
import { activityVisibleForSave } from '../activity/requirements'
import { eligiblePoolEntries } from '../activity/pools'
import { isStandardProductionActivity } from '../production/recipes'
import {
  isThieveryLockpickAction,
  isThieveryShopAction,
  THIEVERY_SKILL_ID,
} from '../skills/skillActions'
import type { PlayerSave } from '../save/types'

function thieveryActionsForActivity(db: GameDatabase, activity: ActivityRow) {
  const poolId = activity['Pool ID']
  if (!poolId) return []
  return eligiblePoolEntries(db, poolId)
    .map((entry) => entry.action)
    .filter((action) => action['Relevant Skill ID'] === THIEVERY_SKILL_ID)
}

function isBankThieveryAction(action: { Notes?: string | null }): boolean {
  return /BankThievery/i.test(action.Notes ?? '')
}

/** Deposit-box / vault picks that belong with the Bank panel. */
export function isBankThieveryActivity(db: GameDatabase, activity: ActivityRow): boolean {
  return thieveryActionsForActivity(db, activity).some(isBankThieveryAction)
}

/**
 * Shop steals listed under the Shops tab when this location has a merchant.
 * Kitchen steals stay on Produce (no shop row; production blocks People routing).
 */
export function isShopThieveryActivity(
  db: GameDatabase,
  _save: PlayerSave,
  activity: ActivityRow,
): boolean {
  if (!thieveryActionsForActivity(db, activity).some(isThieveryShopAction)) return false
  const shops = db.Shops.filter((shop) => shop['Location ID'] === activity['Location ID'])
  return shops.length > 0
}

/**
 * NPC-targeted steals (barracks) when there is no shop.
 * Kitchen / production sites keep steals on Produce even if an NPC is present.
 */
export function isNpcThieveryActivity(
  db: GameDatabase,
  save: PlayerSave,
  activity: ActivityRow,
): boolean {
  if (!thieveryActionsForActivity(db, activity).some(isThieveryShopAction)) return false
  if (isShopThieveryActivity(db, save, activity)) return false
  if (locationHasProductionWorkstation(db, save, activity['Location ID'])) return false
  return db.NPCs.some((npc) => npc['Location ID'] === activity['Location ID'])
}

function locationHasProductionWorkstation(
  db: GameDatabase,
  save: PlayerSave,
  locationId: string,
): boolean {
  return db.Activities.some(
    (row) =>
      row['Location ID'] === locationId &&
      isStandardProductionActivity(db, row) &&
      activityVisibleForSave(db, save, row['Activity ID']),
  )
}

/**
 * Thievery that belongs on Produce with kitchen/workstation crafts
 * (not Shops / People / Bank).
 */
export function isActivityBandThievery(
  db: GameDatabase,
  save: PlayerSave,
  activity: ActivityRow,
): boolean {
  const actions = thieveryActionsForActivity(db, activity)
  if (actions.length === 0) return false
  if (isBankThieveryActivity(db, activity)) return false
  if (isShopThieveryActivity(db, save, activity)) return false
  if (isNpcThieveryActivity(db, save, activity)) return false
  return actions.some(isThieveryLockpickAction) || actions.some(isThieveryShopAction)
}

/** Standard production stations plus Produce-band thievery (kitchen steal, non-bank lockpicks). */
export function isProduceBandActivity(
  db: GameDatabase,
  save: PlayerSave,
  activity: ActivityRow,
): boolean {
  return isStandardProductionActivity(db, activity) || isActivityBandThievery(db, save, activity)
}

export function isThieveryActivity(db: GameDatabase, activity: ActivityRow): boolean {
  return thieveryActionsForActivity(db, activity).length > 0
}
