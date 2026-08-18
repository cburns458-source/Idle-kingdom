import type { LocationRow } from '../data/types'
import type { InventoryStack } from '../save/types'
import { GUILD_HALL_LOCATION_ID } from '../world/constants'

export function locationHasGuildHall(location: LocationRow | undefined | null): boolean {
  if (!location) return false
  return location['Location ID'] === GUILD_HALL_LOCATION_ID
}

/** Recruits cannot pay the hall debt. Member and every rank above can. */
export function canPayGuildDebt(role: string): boolean {
  return role === 'leader' || role === 'officer' || role === 'veteran' || role === 'member'
}

export const GUILD_HALL_DEBT_GOLD = 1_000_000

export interface GuildHallTierCost {
  itemId: string
  quantity: number
}

/**
 * What a guild owes for one step of its hall, and what that step opens.
 *
 * The materials are read out of the storehouse, so a donation is a deposit that
 * happens to count. Finishing a tier spends them.
 */
export interface GuildHallTier {
  id: string
  name: string
  /** One line for the tier card, saying what the guild gets out of it. */
  blurb: string
  /** The quantities the guild must put in, in listing order. */
  cost: GuildHallTierCost[]
  /**
   * What opens in the hall when the tier is finished, absent when the tier is
   * only the building itself.
   */
  unlock?: string
}

/** Reading of one material against what a tier asks for. */
export interface GuildHallTierNeed {
  itemId: string
  needed: number
  have: number
  met: boolean
  /** Capped at `needed`, so a card never reads past full. */
  counted: number
}

export const GUILD_HALL_TIER_BUILD = 'build_the_hall'
export const GUILD_HALL_TIER_BANK = 'hall_bank'
export const GUILD_HALL_TIER_BOXING = 'hall_boxing_ring'

export const GUILD_HALL_UNLOCK_BANK = 'bank'
export const GUILD_HALL_UNLOCK_BOXING = 'boxing_ring'

/** The three steps of a hall, finished in this order. */
export const GUILD_HALL_TIERS: GuildHallTier[] = [
  {
    id: GUILD_HALL_TIER_BUILD,
    name: 'Build the Hall',
    blurb: 'Raise the hall itself. Nothing opens yet.',
    cost: [
      { itemId: 'ITEM-0015', quantity: 1000 },
      { itemId: 'ITEM-0095', quantity: 100 },
    ],
  },
  {
    id: GUILD_HALL_TIER_BANK,
    name: 'Counting Room',
    blurb: 'Opens a bank in the hall.',
    cost: [
      { itemId: 'ITEM-0017', quantity: 1000 },
      { itemId: 'ITEM-0002', quantity: 200 },
      { itemId: 'ITEM-0006', quantity: 100 },
    ],
    unlock: GUILD_HALL_UNLOCK_BANK,
  },
  {
    id: GUILD_HALL_TIER_BOXING,
    name: 'Boxing Ring',
    blurb: 'Opens the ring, where guildmates spar.',
    cost: [
      { itemId: 'ITEM-0002', quantity: 300 },
      { itemId: 'ITEM-0095', quantity: 300 },
      { itemId: 'ITEM-0017', quantity: 300 },
    ],
    unlock: GUILD_HALL_UNLOCK_BOXING,
  },
]

/** The tier a guild is working on, or null once the hall is finished. */
export function nextGuildHallTier(completedTiers: string[]): GuildHallTier | null {
  return GUILD_HALL_TIERS.find((tier) => !completedTiers.includes(tier.id)) ?? null
}

/**
 * How many of `itemId` the next unfinished step will still take.
 *
 * Zero when the hall is finished, when the item is not on that step, or when
 * the storehouse already holds enough. A donation uses this as a cap so extra
 * stays in the bag.
 */
export function guildHallDonationCap(
  completedTiers: string[],
  storehouse: InventoryStack[],
  itemId: string,
): number {
  const tier = nextGuildHallTier(completedTiers)
  if (!tier) return 0
  const need = guildHallTierNeeds(tier, storehouse).find((row) => row.itemId === itemId)
  return need ? need.needed - need.counted : 0
}

/** How far the storehouse gets a tier, material by material. */
export function guildHallTierNeeds(
  tier: GuildHallTier,
  storehouse: InventoryStack[],
): GuildHallTierNeed[] {
  return tier.cost.map((cost) => {
    const have = storehouse.reduce(
      (sum, stack) => (stack.itemId === cost.itemId ? sum + stack.quantity : sum),
      0,
    )
    return {
      itemId: cost.itemId,
      needed: cost.quantity,
      have,
      met: have >= cost.quantity,
      counted: Math.min(have, cost.quantity),
    }
  })
}

export function guildHallTierMet(tier: GuildHallTier, storehouse: InventoryStack[]): boolean {
  return guildHallTierNeeds(tier, storehouse).every((need) => need.met)
}

/**
 * The storehouse once a finished tier has taken its materials out of it.
 *
 * Stacks are drawn down in the order they sit in, and an emptied stack goes.
 */
export function spendGuildHallTier(
  tier: GuildHallTier,
  storehouse: InventoryStack[],
): InventoryStack[] {
  const owed = new Map<string, number>()
  for (const cost of tier.cost) {
    owed.set(cost.itemId, (owed.get(cost.itemId) ?? 0) + cost.quantity)
  }
  const left: InventoryStack[] = []
  for (const stack of storehouse) {
    const due = owed.get(stack.itemId) ?? 0
    if (due <= 0) {
      left.push(stack)
      continue
    }
    if (due >= stack.quantity) {
      owed.set(stack.itemId, due - stack.quantity)
      continue
    }
    owed.set(stack.itemId, 0)
    left.push({ ...stack, quantity: stack.quantity - due })
  }
  return left
}

/** A storehouse deposit settled against the tiers it just paid for. */
export interface GuildHallTierSettlement {
  storehouse: InventoryStack[]
  completedTiers: string[]
  /** The tiers this settlement finished, in the order they were finished. */
  finishedNow: GuildHallTier[]
}

/**
 * Finishes every tier the storehouse now covers, spending its materials.
 *
 * Runs in a loop because one large donation can cover more than one tier.
 */
export function settleGuildHallTiers(
  storehouse: InventoryStack[],
  completedTiers: string[],
): GuildHallTierSettlement {
  let store = storehouse
  const done = [...completedTiers]
  const finishedNow: GuildHallTier[] = []
  for (;;) {
    const tier = nextGuildHallTier(done)
    if (!tier || !guildHallTierMet(tier, store)) break
    store = spendGuildHallTier(tier, store)
    done.push(tier.id)
    finishedNow.push(tier)
  }
  return { storehouse: store, completedTiers: done, finishedNow }
}

export function guildHallHasUnlock(completedTiers: string[], unlock: string): boolean {
  return GUILD_HALL_TIERS.some((tier) => tier.unlock === unlock && completedTiers.includes(tier.id))
}

export function guildHallBankUnlocked(completedTiers: string[]): boolean {
  return guildHallHasUnlock(completedTiers, GUILD_HALL_UNLOCK_BANK)
}

export function guildHallBoxingUnlocked(completedTiers: string[]): boolean {
  return guildHallHasUnlock(completedTiers, GUILD_HALL_UNLOCK_BOXING)
}
