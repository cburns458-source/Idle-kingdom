export interface ActiveActionState {
  actionId: string
  startedAtMs: number
  durationMs: number
}

export interface LootGrant {
  itemId: string
  quantity: number
  displayName: string
}

export interface BonusXpGrant {
  skillId: string
  xp: number
}

export interface ActionXpRewardSummary {
  skillId: string
  skillName: string
  skillKey: string
  xp: number
  level: number
  leveledUp: boolean
}

export interface ActionCompletionResult {
  actionId: string
  actionName: string
  skillId: string
  xpGained: number
  /** Extra skill XP beyond the action's primary Relevant Skill reward. */
  bonusXp: BonusXpGrant[]
  /** Ordered XP reward summaries for the action reward UI. */
  xpRewards: ActionXpRewardSummary[]
  goldGained: number
  loot: LootGrant[]
  leveledUpTo: number | null
}

export interface ActivityStartFailure {
  ok: false
  reason: string
}

export interface ActivityStartSuccess {
  ok: true
}

export type ActivityStartResult = ActivityStartFailure | ActivityStartSuccess
