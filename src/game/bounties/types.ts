export type BountyObjectiveKind = 'defeat' | 'gather_deliver' | 'process' | 'project'

export interface BountyDefinition {
  id: string
  title: string
  description: string
  kind: BountyObjectiveKind
  targetId: string
  amount: number
  rewardGold: number
  /** Extra gold for the first valid turn-in this hour. */
  firstPlaceBonusGold: number
}

export interface BountyClaimRecord {
  hourKey: string
  bountyId: string
  userId: string
  username: string
  claimedAt: string
}

export interface HourlyBountyBoard {
  hourKey: string
  expiresAtMs: number
  bounties: BountyDefinition[]
}
