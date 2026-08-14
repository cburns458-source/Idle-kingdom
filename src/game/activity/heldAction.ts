import type { PlayerSave } from '../save/types'

/** The unfinished pool action remembered for [activityId], if any. */
export function heldActionIdFor(save: PlayerSave, activityId: string | null | undefined): string | null {
  if (!activityId) return null
  const id = save.heldActionByActivityId[activityId]
  return id ? id : null
}

/** Remembers [actionId] for [activityId] until that action finishes. */
export function withHeldAction(save: PlayerSave, activityId: string, actionId: string): PlayerSave {
  return {
    ...save,
    heldActionByActivityId: {
      ...save.heldActionByActivityId,
      [activityId]: actionId,
    },
  }
}

/** Forgets the unfinished action for [activityId] after it completes or a defeat. */
export function withoutHeldAction(save: PlayerSave, activityId: string | null | undefined): PlayerSave {
  if (!activityId || save.heldActionByActivityId[activityId] == null) return save
  const next = { ...save.heldActionByActivityId }
  delete next[activityId]
  return { ...save, heldActionByActivityId: next }
}
