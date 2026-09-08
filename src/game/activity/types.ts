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

/** One completed action's combined reward line (all XP + items). */
export interface ActionRewardBundle {
  id: string
  xpRewards: ActionXpRewardSummary[]
  loot: LootGrant[]
  goldGained: number
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
  /** HP lost on a thievery failure (for combat-style floaters). */
  damageTaken?: number
  /** Food healed after a thievery resolution. */
  foodHealed?: number
  /** Lockpick actions show a 0 damage floater like a combat swing. */
  showZeroDamageHit?: boolean
  thieveryFailed?: boolean
  lockpickBroke?: boolean
}

export interface ActivityStartFailure {
  ok: false
  reason: string
}

export interface ActivityStartSuccess {
  ok: true
}

export type ActivityStartResult = ActivityStartFailure | ActivityStartSuccess
