import type { InventoryStack } from '../save/types'
import { GUILD_HALL_GOLD_CAP, settleGuildHallTiers } from './hall'
import {
  GUILD_HALL_GOLD_CAP_REFUSAL,
  GUILD_HALL_GOLD_OVERPAY_REFUSAL,
  normalizeGuildHallState,
  type GuildHallState,
} from './economy'

export const GUILD_HALL_BANK_MISMATCH_REFUSAL = 'The guild bank change did not match the save.'

type StackLike = {
  itemId: string
  quantity: number
  enchantmentId?: string | null
}

export type GuildHallCommitProposal = {
  /** Ignored. The running total is previous gold minus new gold, never this. */
  goldContributed?: number
  /** Ignored. Tiers finish only from verified gold + storehouse. */
  completedTiers?: string[]
  storehouse?: StackLike[]
  bankItems?: StackLike[]
}

export type GuildHallCommitInput = {
  previousGold: number
  nextGold: number
  previousInventory: StackLike[]
  nextInventory: StackLike[]
  hall: GuildHallState
  previousBankItems?: StackLike[]
  proposed?: GuildHallCommitProposal
  userId: string
}

export type GuildHallCommitResult =
  | {
      ok: true
      goldTaken: number
      hall: GuildHallState
      bankItems: StackLike[]
      finishedNow: string[]
    }
  | { ok: false; reason: string }

const KEY_SEP = '\u001f'

export function goldTakenFromPlayerSaves(previousGold: number, nextGold: number): number {
  const before = Number.isFinite(previousGold) ? Math.floor(previousGold) : 0
  const after = Number.isFinite(nextGold) ? Math.floor(nextGold) : 0
  return Math.max(0, before - after)
}

export function stackQtyKey(stack: StackLike): string {
  return `${stack.itemId}${KEY_SEP}${stack.enchantmentId ?? ''}`
}

export function qtyByKey(stacks: StackLike[] | null | undefined): Map<string, number> {
  const map = new Map<string, number>()
  if (!Array.isArray(stacks)) return map
  for (const stack of stacks) {
    if (!stack || typeof stack.itemId !== 'string' || stack.itemId.length === 0) continue
    const qty = Math.max(0, Math.floor(Number(stack.quantity) || 0))
    if (qty <= 0) continue
    const key = stackQtyKey(stack)
    map.set(key, (map.get(key) ?? 0) + qty)
  }
  return map
}

function parseQtyKey(key: string): { itemId: string; enchantmentId: string | null } {
  const at = key.indexOf(KEY_SEP)
  if (at < 0) return { itemId: key, enchantmentId: null }
  const enchantmentId = key.slice(at + 1)
  return { itemId: key.slice(0, at), enchantmentId: enchantmentId.length > 0 ? enchantmentId : null }
}

function qtyOf(map: Map<string, number>, key: string): number {
  return map.get(key) ?? 0
}

function allKeys(...maps: Map<string, number>[]): string[] {
  const keys = new Set<string>()
  for (const map of maps) {
    for (const key of map.keys()) keys.add(key)
  }
  return [...keys]
}

export function addToGuildHallStorehouse(
  storehouse: InventoryStack[],
  itemId: string,
  quantity: number,
  enchantmentId: string | null = null,
): InventoryStack[] {
  const want = Math.max(0, Math.floor(quantity))
  if (want <= 0) return storehouse
  if (enchantmentId) {
    return [...storehouse, { itemId, quantity: want, enchantmentId }]
  }
  const at = storehouse.findIndex((stack) => stack.itemId === itemId && !stack.enchantmentId)
  if (at < 0) return [...storehouse, { itemId, quantity: want }]
  const next = [...storehouse]
  next[at] = { ...next[at], quantity: next[at].quantity + want }
  return next
}

export function takeFromGuildHallStorehouse(
  storehouse: InventoryStack[],
  itemId: string,
  quantity: number,
  enchantmentId: string | null = null,
): InventoryStack[] {
  let owed = Math.max(0, Math.floor(quantity))
  if (owed <= 0) return storehouse
  const left: InventoryStack[] = []
  for (const stack of storehouse) {
    const sameEnchant = (stack.enchantmentId ?? null) === (enchantmentId ?? null)
    if (owed <= 0 || stack.itemId !== itemId || !sameEnchant) {
      left.push(stack)
      continue
    }
    if (owed >= stack.quantity) {
      owed -= stack.quantity
      continue
    }
    left.push({ ...stack, quantity: stack.quantity - owed })
    owed = 0
  }
  return left
}

/**
 * Hall gold, storehouse, and finished tiers from the save immediately before
 * the hall command versus after it. Catch-up must already be applied to
 * `previous*`. A payload that names `goldContributed` / `completedTiers` is
 * ignored. Over-cap gold and a mismatched bank are refused, not truncated.
 */
export function commitGuildHallFromPlayerSaves(input: GuildHallCommitInput): GuildHallCommitResult {
  const current = normalizeGuildHallState(input.hall)
  const remaining = Math.max(0, GUILD_HALL_GOLD_CAP - current.goldContributed)
  const goldDelta = goldTakenFromPlayerSaves(input.previousGold, input.nextGold)
  if (goldDelta > remaining) {
    return {
      ok: false,
      reason: remaining <= 0 ? GUILD_HALL_GOLD_CAP_REFUSAL : GUILD_HALL_GOLD_OVERPAY_REFUSAL,
    }
  }
  const goldTaken = goldDelta
  const goldContributed = current.goldContributed + goldTaken
  const goldContributedBy = { ...current.goldContributedBy }
  if (goldTaken > 0 && input.userId) {
    goldContributedBy[input.userId] = (goldContributedBy[input.userId] ?? 0) + goldTaken
  }

  const previousInv = qtyByKey(input.previousInventory)
  const nextInv = qtyByKey(input.nextInventory)
  const oldBank = qtyByKey(input.previousBankItems ?? [])
  const proposedBank = qtyByKey(input.proposed?.bankItems ?? input.previousBankItems ?? [])
  const oldStore = qtyByKey(current.storehouse)
  const proposedStore = qtyByKey(input.proposed?.storehouse ?? current.storehouse)

  let storehouse = [...current.storehouse]
  for (const key of allKeys(previousInv, nextInv, oldBank, proposedBank, oldStore, proposedStore)) {
    const lost = Math.max(0, qtyOf(previousInv, key) - qtyOf(nextInv, key))
    const gained = Math.max(0, qtyOf(nextInv, key) - qtyOf(previousInv, key))
    const bankGain = Math.min(Math.max(0, qtyOf(proposedBank, key) - qtyOf(oldBank, key)), lost)
    const bankLoss = Math.min(Math.max(0, qtyOf(oldBank, key) - qtyOf(proposedBank, key)), gained)
    const expectedBank = qtyOf(oldBank, key) + bankGain - bankLoss
    if (qtyOf(proposedBank, key) !== expectedBank) {
      return { ok: false, reason: GUILD_HALL_BANK_MISMATCH_REFUSAL }
    }
    const donated = lost - bankGain
    const withdrawn = Math.min(
      gained - bankLoss,
      Math.max(0, qtyOf(oldStore, key) - qtyOf(proposedStore, key)),
    )
    const { itemId, enchantmentId } = parseQtyKey(key)
    if (donated > 0) storehouse = addToGuildHallStorehouse(storehouse, itemId, donated, enchantmentId)
    if (withdrawn > 0) storehouse = takeFromGuildHallStorehouse(storehouse, itemId, withdrawn, enchantmentId)
  }

  const settled = settleGuildHallTiers(storehouse, current.completedTiers, goldContributed)
  const hall = normalizeGuildHallState({
    ...current,
    goldContributed,
    goldContributedBy,
    storehouse: settled.storehouse,
    completedTiers: settled.completedTiers,
  })
  return {
    ok: true,
    goldTaken,
    hall,
    bankItems: input.proposed?.bankItems ?? input.previousBankItems ?? [],
    finishedNow: settled.finishedNow.map((tier) => tier.id),
  }
}
