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
  talkNpcIds: string[]
  visitLocationIds: string[]
  inspectIds: string[]
  goldCost: number
  acceptGoldCost: number
  rewardGold: number
  bribeGold: number
  branchSkillXp: number
  choiceNpcId: string | null
  turnInNpcId: string | null
  autoStartLocationId: string | null
  unlockLocationIds: string[]
  rewardRecipeIds: string[]
  rewardProjectNpcIds: string[]
  rewardCosmeticIds: string[]
}
