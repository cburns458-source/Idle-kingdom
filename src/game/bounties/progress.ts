import type { PlayerSave } from '../save/types'
import { hourlyBountyBoard } from './rotation'
import type { BountyDefinition, BountyObjectiveKind } from './types'

function emptyProgress(): Record<string, number> {
  return {}
}

/** Ensure save bounty counters match the current UTC hour board. */
export function syncBountyHour(save: PlayerSave, nowMs: number = Date.now()): PlayerSave {
  const board = hourlyBountyBoard(nowMs)
  if (save.bountyHourKey === board.hourKey) return save
  return {
    ...save,
    bountyHourKey: board.hourKey,
    bountyProgress: emptyProgress(),
    bountyClaimedIds: [],
  }
}

function bumpMatching(
  save: PlayerSave,
  kind: BountyObjectiveKind,
  targetId: string,
  amount: number,
  nowMs: number,
): PlayerSave {
  if (amount <= 0) return save
  let next = syncBountyHour(save, nowMs)
  const board = hourlyBountyBoard(nowMs)
  const progress = { ...(next.bountyProgress ?? {}) }
  let changed = false
  for (const bounty of board.bounties) {
    if (bounty.kind !== kind || bounty.targetId !== targetId) continue
    if ((next.bountyClaimedIds ?? []).includes(bounty.id)) continue
    const current = Number(progress[bounty.id] ?? 0)
    if (current >= bounty.amount) continue
    progress[bounty.id] = Math.min(bounty.amount, current + amount)
    changed = true
  }
  if (!changed) return next
  return { ...next, bountyProgress: progress }
}

export function applyBountyGatherProgress(
  save: PlayerSave,
  itemId: string,
  amount: number,
  nowMs: number = Date.now(),
): PlayerSave {
  return bumpMatching(save, 'gather_item', itemId, amount, nowMs)
}

export function applyBountyDefeatProgress(
  save: PlayerSave,
  enemyId: string,
  amount = 1,
  nowMs: number = Date.now(),
): PlayerSave {
  return bumpMatching(save, 'defeat_enemy', enemyId, amount, nowMs)
}

export function applyBountyProcessProgress(
  save: PlayerSave,
  recipeId: string,
  amount = 1,
  nowMs: number = Date.now(),
): PlayerSave {
  return bumpMatching(save, 'process_recipe', recipeId, amount, nowMs)
}

export function bountyProgressFor(
  save: PlayerSave,
  bounty: BountyDefinition,
  nowMs: number = Date.now(),
): number {
  const synced = syncBountyHour(save, nowMs)
  return Number(synced.bountyProgress?.[bounty.id] ?? 0)
}

export function isBountyReadyToClaim(
  save: PlayerSave,
  bounty: BountyDefinition,
  nowMs: number = Date.now(),
): boolean {
  const synced = syncBountyHour(save, nowMs)
  if ((synced.bountyClaimedIds ?? []).includes(bounty.id)) return false
  return bountyProgressFor(synced, bounty, nowMs) >= bounty.amount
}
