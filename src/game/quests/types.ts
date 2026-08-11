/** Normalized quest objective kinds from the Bible §14.4 list. */
export type QuestObjectiveKind =
  | 'gather_deliver'
  | 'process'
  | 'defeat'
  | 'learn_recipe'
  | 'restore_facility'
  | 'construct_portal'
  | 'unlock_travel'
  | 'guild_collab'

export interface QuestCounterTarget {
  /** ITEM / ENM / RCP / PRJ / LOC / FAC id depending on kind. */
  targetId: string
  quantity: number
}

export interface StructuredQuestObjectives {
  kind: QuestObjectiveKind
  delivers: QuestCounterTarget[]
  processTargets: QuestCounterTarget[]
  defeatTargets: QuestCounterTarget[]
  learnRecipeIds: string[]
  restoreFacilityIds: string[]
  constructPortalIds: string[]
  unlockTravelIds: string[]
  goldCost: number
  unlockLocationIds: string[]
  rewardRecipeIds: string[]
  rewardProjectNpcIds: string[]
}
