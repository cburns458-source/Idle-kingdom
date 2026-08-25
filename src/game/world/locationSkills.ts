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

/** Skill IDs that have a visible gathering, combat, or production action here. */
export function skillIdsForLocation(
  db: GameDatabase,
  save: PlayerSave,
  locationId: string,
): string[] {
  const ids = new Set<string>()

  for (const activity of db.Activities) {
    if (activity['Location ID'] !== locationId) continue
    if (!activityVisibleForSave(db, save, activity['Activity ID'])) continue

    const poolId = activity['Pool ID']
    if (poolId) {
      for (const candidate of eligiblePoolEntries(db, poolId)) {
        const skillId = candidate.action['Relevant Skill ID']
        if (skillId) ids.add(skillId)
      }
    }

    if (isStandardProductionActivity(db, activity)) {
      const facilityId = facilityIdForActivity(db, activity['Activity ID'])
      if (!facilityId) continue
      for (const recipe of db.Recipes) {
        if (!isCompleteRecipe(recipe)) continue
        if (!recipeMatchesFacility(recipe['Facility ID'], facilityId)) continue
        if (recipe['Skill ID']) ids.add(recipe['Skill ID'])
      }
    }
  }

  for (const station of specialProductionStationsVisibleAt(db, save, locationId)) {
    if (station.skillId) ids.add(station.skillId)
  }

  const order = db.Skills.map((skill) => skill['Skill ID'])
  return [...ids].sort((a, b) => {
    const aIndex = order.indexOf(a)
    const bIndex = order.indexOf(b)
    return (aIndex < 0 ? 1e6 : aIndex) - (bIndex < 0 ? 1e6 : bIndex)
  })
}
