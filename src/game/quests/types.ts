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
  optionalTalkNpcIds: string[]
  visitLocationIds: string[]
  inspectIds: string[]
  /** Show these items; they are not taken on turn-in. */
  holds: QuestCounterTarget[]
  /** Gathering/combat actions that count toward the step. */
  actionTargets: QuestCounterTarget[]
  requiresSkills: Array<{ skillId: string; level: number }>
  requiresQuestIds: string[]
  unlockOnAcceptLocationIds: string[]
  rewardXp: Array<{ skillId: string; amount: number }>
  goldCost: number
  acceptGoldCost: number
  rewardGold: number
  bribeGold: number
  branchSkillXp: number
  choiceNpcId: string | null
  turnInNpcId: string | null
  autoStartLocationId: string | null
  /** Complete the quest when the last Talk finishes, with no Turn in. */
  autoCompleteOnTalk: boolean
  /** Complete the quest when the last Visit finishes. */
  autoCompleteOnVisit: boolean
  unlockLocationIds: string[]
  rewardRecipeIds: string[]
  rewardProjectNpcIds: string[]
  rewardCosmeticIds: string[]
}
