export type BountyObjectiveKind = 'gather_item' | 'defeat_enemy' | 'process_recipe'

export interface BountyDefinition {
  id: string
  title: string
  description: string
  kind: BountyObjectiveKind
  targetId: string
  amount: number
  rewardGold: number
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
