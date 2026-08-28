import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import { MAIN_MAP_ID } from '../world/constants'
import { getLocationMapId } from '../world/travel'
import { hasQuestFlag } from './progress'
import { asQuestRows, getQuestProgress } from './quests'
import { questActiveStepObjectives } from './steps'

/** First unvisited Visit target on an active quest step. */
export function questVisitHintLocationId(db: GameDatabase, save: PlayerSave): string | null {
  for (const quest of asQuestRows(db)) {
    const questId = quest['Quest ID']
    if (getQuestProgress(save, questId).status !== 'active') continue
    const step = questActiveStepObjectives(db, save, quest)
    if (!step) continue
    for (const locationId of step.visitLocationIds) {
      if (!hasQuestFlag(save, questId, `visit:${locationId}`)) return locationId
    }
  }
  return null
}

/** Map node to pulse on [browseMapId], or null. */
export function questHintNodeId(
  db: GameDatabase,
  save: PlayerSave,
  browseMapId: string,
): string | null {
  const hintId = questVisitHintLocationId(db, save)
  if (!hintId) return null
  const hint = db.Locations.find((row) => row['Location ID'] === hintId)
  if (!hint) return null
  if (getLocationMapId(hint) === browseMapId) return hintId

  let parentId = typeof hint['Parent Location ID'] === 'string' ? hint['Parent Location ID'] : null
  while (parentId) {
    const parent = db.Locations.find((row) => row['Location ID'] === parentId)
    if (!parent) break
    if (getLocationMapId(parent) === browseMapId) return parentId
    parentId =
      typeof parent['Parent Location ID'] === 'string' ? parent['Parent Location ID'] : null
  }

  if (browseMapId === MAIN_MAP_ID) {
    const hintMapId = getLocationMapId(hint)
    const gateway = db.Locations.find((row) => {
      if (getLocationMapId(row) !== MAIN_MAP_ID) return false
      if (!(row['Location Type'] ?? '').toLowerCase().includes('sub-map gateway')) return false
      return db.Locations.some(
        (child) =>
          child['Parent Location ID'] === row['Location ID'] && getLocationMapId(child) === hintMapId,
      )
    })
    return gateway?.['Location ID'] ?? null
  }
  return null
}

/** Pulse the location-screen world-map chip while a Visit hint is outstanding. */
export function questHintsWorldMapButton(db: GameDatabase, save: PlayerSave): boolean {
  const hintId = questVisitHintLocationId(db, save)
  return hintId != null && save.currentLocationId !== hintId
}
