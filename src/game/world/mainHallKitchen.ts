import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'

/** Castle Main Hall cook station. */
export const MAIN_HALL_COOK_ACTIVITY_ID = 'ACT-0023'

/** Grand Feast must be accepted before the Main Hall kitchen may be used. */
export const GRAND_FEAST_QUEST_ID = 'QST-0001'

export const MAIN_HALL_KITCHEN_LOCKED_MESSAGE =
  "I shouldn't cook here without permission"

/** True once Grand Feast is active or finished on this save. */
export function grandFeastStarted(save: PlayerSave): boolean {
  return (save.quests ?? []).some(
    (row) =>
      row.questId === GRAND_FEAST_QUEST_ID &&
      (row.status === 'active' || row.status === 'completed'),
  )
}

export function mainHallKitchenLocked(
  _db: GameDatabase,
  save: PlayerSave,
  activityId: string,
): boolean {
  return activityId === MAIN_HALL_COOK_ACTIVITY_ID && !grandFeastStarted(save)
}
