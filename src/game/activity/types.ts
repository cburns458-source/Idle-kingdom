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

/** One row per itemId, quantities summed, first displayName kept, then sorted. */
export function mergeLeftBehind(grants: readonly LootGrant[]): LootGrant[] {
  const byId = new Map<string, LootGrant>()
  for (const grant of grants) {
    if (grant.quantity <= 0) continue
    const existing = byId.get(grant.itemId)
    if (existing) {
      existing.quantity += grant.quantity
    } else {
      byId.set(grant.itemId, { ...grant })
    }
  }
  return [...byId.values()].sort((left, right) => left.itemId.localeCompare(right.itemId))
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
  /** Wardrobe cosmetics unlocked with this reward line (e.g. Baby Dragon pet). */
  cosmeticsGranted?: { cosmeticId: string; isFirstEver: boolean }[]
  /** Library books unlocked with this reward line. Omitted when empty. */
  booksGranted?: { bookId: string; isFirstEver: boolean }[]
  /** Drops that rolled but did not fit in the bag. Same shape as `loot`. */
  leftBehind?: LootGrant[]
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
  /** Wardrobe cosmetics unlocked by this action (e.g. Baby Dragon pet). */
  cosmeticsGranted?: { cosmeticId: string; isFirstEver: boolean }[]
  /** Library books unlocked by this action. Omitted when empty. */
  booksGranted?: { bookId: string; isFirstEver: boolean }[]
  /** Drops that rolled but did not fit in the bag. Same shape as `loot`. */
  leftBehind?: LootGrant[]
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
