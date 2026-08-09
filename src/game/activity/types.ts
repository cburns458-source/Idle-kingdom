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

export interface ActionCompletionResult {
  actionId: string
  actionName: string
  skillId: string
  xpGained: number
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
