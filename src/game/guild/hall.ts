import type { LocationRow } from '../data/types'
import type { InventoryStack } from '../save/types'
import { GUILD_HALL_LOCATION_ID } from '../world/constants'

export function locationHasGuildHall(location: LocationRow | undefined | null): boolean {
  if (!location) return false
  return location['Location ID'] === GUILD_HALL_LOCATION_ID
}

/** Recruits cannot chip in gold. Member and every rank above can. */
export function canChipInGuildGold(role: string): boolean {
  return role === 'leader' || role === 'officer' || role === 'veteran' || role === 'member'
}

/** @deprecated Use canChipInGuildGold. Recruits still cannot chip in. */
export function canPayGuildDebt(role: string): boolean {
  return canChipInGuildGold(role)
}

/** Running gold total members chip into. Caps chip-ins; not a stored gold pool. */
export const GUILD_HALL_GOLD_CAP = 1_000_000

/** @deprecated The old 1M debt is the same cap as the running gold total. */
export const GUILD_HALL_DEBT_GOLD = GUILD_HALL_GOLD_CAP

export const GUILD_HALL_GOLD_MARKS = [10_000, 40_000, 130_000, 400_000, 1_000_000] as const

export interface GuildHallTierCost {
  itemId: string
  quantity: number
}

/**
 * What a guild owes for one step of its hall, and what that step opens.
 *
 * The materials are read out of the storehouse, so a donation is a deposit that
 * happens to count. Finishing a tier spends them. Gold uses one running total;
 * a room tier also needs that total to have reached [goldThreshold].
 */
export interface GuildHallTier {
  id: string
  name: string
  /** One line for the tier card, saying what the guild gets out of it. */
  blurb: string
  /** The quantities the guild must put in, in listing order. */
  cost: GuildHallTierCost[]
  /**
   * Cumulative gold the guild must have chipped in before this tier can finish.
   * Zero for Build the Hall.
   */
  goldThreshold: number
  /**
   * Gold shown on the tier card as this step's cost. Sums of these equal the
   * running-total marks: 10k / 30k / 90k / 270k / 600k.
   */
  goldCost: number
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
export const GUILD_HALL_TIER_GARDEN = 'hall_indoor_garden'
export const GUILD_HALL_TIER_ARCANA = 'hall_arcana_station'
export const GUILD_HALL_TIER_CAGE = 'hall_monster_cage'

export const GUILD_HALL_UNLOCK_BANK = 'bank'
export const GUILD_HALL_UNLOCK_BOXING = 'boxing_ring'
export const GUILD_HALL_UNLOCK_GARDEN = 'indoor_garden'
export const GUILD_HALL_UNLOCK_ARCANA = 'arcana_station'
export const GUILD_HALL_UNLOCK_CAGE = 'monster_cage'

export const GUILD_HALL_TIER_FINISH_LINES: Record<string, string> = {
  [GUILD_HALL_TIER_BANK]: 'The counting room is open for business.',
  [GUILD_HALL_TIER_BOXING]: 'The ring is roped off. Settle your differences in there.',
  [GUILD_HALL_TIER_GARDEN]: "Soil's in, and the hall smells of earth now.",
  [GUILD_HALL_TIER_ARCANA]: 'The Arcana station hums to life in the corner.',
  [GUILD_HALL_TIER_CAGE]: 'Something big is rattling the cage. Mind your fingers.',
}

/** Item ids looked up from content/data/game-database.json Display Name. */
const POPLAR_LOG = 'ITEM-0017'
const CLAY = 'ITEM-0002'
const COAL = 'ITEM-0006'
const THREAD = 'ITEM-0095'
const OAK_LOG = 'ITEM-0016'
const COMPOST = 'ITEM-0377'
const ESSENCE = 'ITEM-0011'
const MAPLE_LOG = 'ITEM-0018'
const STEEL_BAR = 'ITEM-0077'
const IRON_BAR = 'ITEM-0076'
const CEDAR_LOG = 'ITEM-0015'

/** Build the Hall, then the five rooms, finished in this order. */
export const GUILD_HALL_TIERS: GuildHallTier[] = [
  {
    id: GUILD_HALL_TIER_BUILD,
    name: 'Build the Hall',
    blurb: 'Raise the hall itself. Nothing opens yet.',
    cost: [
      { itemId: CEDAR_LOG, quantity: 1000 },
      { itemId: THREAD, quantity: 100 },
    ],
    goldThreshold: 0,
    goldCost: 0,
  },
  {
    id: GUILD_HALL_TIER_BANK,
    name: 'Counting Room',
    blurb: 'Opens a bank in the hall.',
    cost: [
      { itemId: POPLAR_LOG, quantity: 24_000 },
      { itemId: CLAY, quantity: 10_000 },
      { itemId: COAL, quantity: 6_320 },
    ],
    goldThreshold: 10_000,
    goldCost: 10_000,
    unlock: GUILD_HALL_UNLOCK_BANK,
  },
  {
    id: GUILD_HALL_TIER_BOXING,
    name: 'Boxing Ring',
    blurb: 'Opens the ring, where guildmates spar.',
    cost: [
      { itemId: CLAY, quantity: 14_000 },
      { itemId: THREAD, quantity: 13_160 },
      { itemId: POPLAR_LOG, quantity: 13_160 },
    ],
    goldThreshold: 40_000,
    goldCost: 30_000,
    unlock: GUILD_HALL_UNLOCK_BOXING,
  },
  {
    id: GUILD_HALL_TIER_GARDEN,
    name: 'Indoor Garden',
    blurb: 'Opens a garden patch in the hall.',
    cost: [
      { itemId: OAK_LOG, quantity: 20_000 },
      { itemId: CLAY, quantity: 8_320 },
      { itemId: COMPOST, quantity: 12_000 },
    ],
    goldThreshold: 130_000,
    goldCost: 90_000,
    unlock: GUILD_HALL_UNLOCK_GARDEN,
  },
  {
    id: GUILD_HALL_TIER_ARCANA,
    name: 'Arcana Station',
    blurb: 'Opens an Arcana station in the hall.',
    cost: [
      { itemId: ESSENCE, quantity: 16_000 },
      { itemId: MAPLE_LOG, quantity: 16_000 },
      { itemId: CLAY, quantity: 8_320 },
    ],
    goldThreshold: 400_000,
    goldCost: 270_000,
    unlock: GUILD_HALL_UNLOCK_ARCANA,
  },
  {
    id: GUILD_HALL_TIER_CAGE,
    name: 'Monster Cage',
    blurb: 'Opens a training cage. XP only — no loot.',
    cost: [
      { itemId: STEEL_BAR, quantity: 10_000 },
      { itemId: IRON_BAR, quantity: 12_000 },
      { itemId: COAL, quantity: 18_320 },
    ],
    goldThreshold: 1_000_000,
    goldCost: 600_000,
    unlock: GUILD_HALL_UNLOCK_CAGE,
  },
]

/** Paid gold from the old 1M debt, used when loading halls that still store remaining. */
export function goldContributedFromDebtRemaining(debtRemaining: number): number {
  const remaining = Number.isFinite(debtRemaining) ? debtRemaining : GUILD_HALL_GOLD_CAP
  return Math.max(0, Math.min(GUILD_HALL_GOLD_CAP, GUILD_HALL_GOLD_CAP - remaining))
}

export function guildHallGoldRemaining(goldContributed: number): number {
  return Math.max(0, GUILD_HALL_GOLD_CAP - goldContributed)
}

/** How much of a chip-in the running total will still take. */
export function guildHallGoldChipInCap(goldContributed: number): number {
  return guildHallGoldRemaining(goldContributed)
}

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

export function guildHallTierGoldMet(tier: GuildHallTier, goldContributed: number): boolean {
  return goldContributed >= tier.goldThreshold
}

/** How many items a finished tier spent from the storehouse. Bank deposits do not count. */
export function guildHallTierMaterialCount(tier: GuildHallTier): number {
  return tier.cost.reduce((sum, cost) => sum + cost.quantity, 0)
}

/** Materials spent finishing the named hall tiers. Storehouse leftovers do not count. */
export function guildHallMaterialsSpent(completedTiers: string[]): number {
  let spent = 0
  for (const tier of GUILD_HALL_TIERS) {
    if (completedTiers.includes(tier.id)) spent += guildHallTierMaterialCount(tier)
  }
  return spent
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
 * Finishes every tier the storehouse and gold total now cover, spending materials.
 *
 * A room tier unlocks only when its gold threshold is passed AND its materials
 * are in. Tiers finish in order, never twice. Build the Hall has no gold gate.
 */
export function settleGuildHallTiers(
  storehouse: InventoryStack[],
  completedTiers: string[],
  goldContributed = 0,
): GuildHallTierSettlement {
  let store = storehouse
  const done = [...completedTiers]
  const finishedNow: GuildHallTier[] = []
  for (;;) {
    const tier = nextGuildHallTier(done)
    if (!tier || !guildHallTierGoldMet(tier, goldContributed) || !guildHallTierMet(tier, store)) {
      break
    }
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

export function guildHallGardenUnlocked(completedTiers: string[]): boolean {
  return guildHallHasUnlock(completedTiers, GUILD_HALL_UNLOCK_GARDEN)
}

export function guildHallArcanaUnlocked(completedTiers: string[]): boolean {
  return guildHallHasUnlock(completedTiers, GUILD_HALL_UNLOCK_ARCANA)
}

export function guildHallCageUnlocked(completedTiers: string[]): boolean {
  return guildHallHasUnlock(completedTiers, GUILD_HALL_UNLOCK_CAGE)
}

export function guildHallTierFinishLine(tierId: string): string | null {
  return GUILD_HALL_TIER_FINISH_LINES[tierId] ?? null
}
