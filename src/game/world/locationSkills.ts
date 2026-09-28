import { activityVisibleForSave } from '../activity/requirements'
import { eligiblePoolEntries } from '../activity/pools'
import type { GameDatabase } from '../data/types'
import {
  facilityIdForActivity,
  isCompleteRecipe,
  isStandardProductionActivity,
  recipeMatchesFacility,
} from '../production/recipes'
import { specialProductionStationsVisibleAt } from '../projects/projects'
import type { PlayerSave } from '../save/types'

/** Combat actions report Might so activity/map cards show the fighting skill. */
export const COMBAT_DISPLAY_SKILL_ID = 'SKL-0001'

function sortSkillIds(db: GameDatabase, ids: Iterable<string>): string[] {
  const order = db.Skills.map((skill) => skill['Skill ID'])
  return [...ids].sort((a, b) => {
    const aIndex = order.indexOf(a)
    const bIndex = order.indexOf(b)
    return (aIndex < 0 ? 1e6 : aIndex) - (bIndex < 0 ? 1e6 : bIndex)
  })
}

/** Skill IDs shown on one activity card (pool skills and/or production recipes). */
export function skillIdsForActivity(
  db: GameDatabase,
  save: PlayerSave,
  activityId: string,
): string[] {
  const activity = db.Activities.find((row) => row['Activity ID'] === activityId)
  if (!activity) return []
  if (!activityVisibleForSave(db, save, activityId)) return []

  const ids = new Set<string>()
  const poolId = activity['Pool ID']
  if (poolId) {
    for (const candidate of eligiblePoolEntries(db, poolId)) {
      const skillId = candidate.action['Relevant Skill ID']
      if (skillId) ids.add(skillId)
    }
  }

  if (isStandardProductionActivity(db, activity)) {
    const facilityId = facilityIdForActivity(db, activityId)
    if (facilityId) {
      for (const recipe of db.Recipes) {
        if (!isCompleteRecipe(recipe)) continue
        if (!recipeMatchesFacility(recipe['Facility ID'], facilityId)) continue
        if (recipe['Skill ID']) ids.add(recipe['Skill ID'])
      }
    }
  }

  return sortSkillIds(db, ids)
}

/** Skill IDs that have a visible gathering, combat, or production action here. */
export function skillIdsForLocation(
  db: GameDatabase,
  save: PlayerSave,
  locationId: string,
): string[] {
  const ids = new Set<string>()

  for (const activity of db.Activities) {
    if (activity['Location ID'] !== locationId) continue
    for (const skillId of skillIdsForActivity(db, save, activity['Activity ID'])) {
      ids.add(skillId)
    }
  }

  for (const station of specialProductionStationsVisibleAt(db, save, locationId)) {
    if (station.skillId) ids.add(station.skillId)
  }

  return sortSkillIds(db, ids)
}
