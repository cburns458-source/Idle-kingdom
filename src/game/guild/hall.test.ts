import { describe, expect, it } from 'vitest'
import type { InventoryStack } from '../save/types'
import {
  canChipInGuildGold,
  canPayGuildDebt,
  goldContributedFromDebtRemaining,
  GUILD_HALL_GOLD_CAP,
  GUILD_HALL_GOLD_MARKS,
  GUILD_HALL_TIERS,
  GUILD_HALL_TIER_ARCANA,
  GUILD_HALL_TIER_BANK,
  GUILD_HALL_TIER_BOXING,
  GUILD_HALL_TIER_BUILD,
  GUILD_HALL_TIER_CAGE,
  GUILD_HALL_TIER_FINISH_LINES,
  GUILD_HALL_TIER_GARDEN,
  guildHallArcanaUnlocked,
  guildHallBankUnlocked,
  guildHallBoxingUnlocked,
  guildHallCageUnlocked,
  guildHallDonationCap,
  guildHallGardenUnlocked,
  guildHallGoldChipInCap,
  guildHallTierFinishLine,
  guildHallTierGoldMet,
  guildHallTierMet,
  guildHallTierNeeds,
  nextGuildHallTier,
  settleGuildHallTiers,
} from './hall'
import { applyGuildHallCompanyXp } from './rooms'
import { defaultGuildPermissionTable, guildMay, GUILD_BANK_TOTAL_LEVEL_REQUIRED } from './permissions'
import { mergeGuildLogDonation } from './log'

function stack(itemId: string, quantity: number): InventoryStack {
  return { itemId, quantity }
}

describe('guild hall tiers', () => {
  it('recruits cannot chip in gold; member and above can', () => {
    expect(canChipInGuildGold('recruit')).toBe(false)
    expect(canPayGuildDebt('recruit')).toBe(false)
    expect(canChipInGuildGold('member')).toBe(true)
    expect(canChipInGuildGold('leader')).toBe(true)
  })

  it('is built in six steps, in order', () => {
    expect(GUILD_HALL_TIERS.map((tier) => tier.id)).toEqual([
      GUILD_HALL_TIER_BUILD,
      GUILD_HALL_TIER_BANK,
      GUILD_HALL_TIER_BOXING,
      GUILD_HALL_TIER_GARDEN,
      GUILD_HALL_TIER_ARCANA,
      GUILD_HALL_TIER_CAGE,
    ])
    expect(nextGuildHallTier([])?.id).toBe(GUILD_HALL_TIER_BUILD)
    expect(nextGuildHallTier([GUILD_HALL_TIER_BUILD])?.id).toBe(GUILD_HALL_TIER_BANK)
    expect(
      nextGuildHallTier([
        GUILD_HALL_TIER_BUILD,
        GUILD_HALL_TIER_BANK,
        GUILD_HALL_TIER_BOXING,
        GUILD_HALL_TIER_GARDEN,
        GUILD_HALL_TIER_ARCANA,
        GUILD_HALL_TIER_CAGE,
      ]),
    ).toBeNull()
  })

  it('asks for cedar logs and thread first, and opens nothing for them', () => {
    const build = GUILD_HALL_TIERS[0]
    expect(build.unlock).toBeUndefined()
    expect(build.goldThreshold).toBe(0)
    expect(build.cost).toEqual([
      { itemId: 'ITEM-0015', quantity: 1000 },
      { itemId: 'ITEM-0095', quantity: 100 },
    ])
  })

  it('uses the listed room costs, gold marks, and display costs', () => {
    expect(GUILD_HALL_GOLD_MARKS).toEqual([10_000, 40_000, 130_000, 400_000, 1_000_000])
    expect(GUILD_HALL_TIERS.slice(1).map((tier) => tier.goldThreshold)).toEqual([...GUILD_HALL_GOLD_MARKS])
    expect(GUILD_HALL_TIERS.slice(1).map((tier) => tier.goldCost)).toEqual([
      10_000, 30_000, 90_000, 270_000, 600_000,
    ])
    expect(GUILD_HALL_TIERS[1].cost).toEqual([
      { itemId: 'ITEM-0017', quantity: 24_000 },
      { itemId: 'ITEM-0002', quantity: 10_000 },
      { itemId: 'ITEM-0006', quantity: 6_320 },
    ])
    expect(GUILD_HALL_TIERS[5].cost).toEqual([
      { itemId: 'ITEM-0077', quantity: 10_000 },
      { itemId: 'ITEM-0076', quantity: 12_000 },
      { itemId: 'ITEM-0006', quantity: 18_320 },
    ])
  })

  it('opens each room only when that tier id is finished', () => {
    expect(guildHallBankUnlocked([GUILD_HALL_TIER_BUILD])).toBe(false)
    expect(guildHallBankUnlocked([GUILD_HALL_TIER_BANK])).toBe(true)
    expect(guildHallBoxingUnlocked([GUILD_HALL_TIER_BANK])).toBe(false)
    expect(guildHallBoxingUnlocked([GUILD_HALL_TIER_BOXING])).toBe(true)
    expect(guildHallGardenUnlocked([GUILD_HALL_TIER_GARDEN])).toBe(true)
    expect(guildHallArcanaUnlocked([GUILD_HALL_TIER_ARCANA])).toBe(true)
    expect(guildHallCageUnlocked([GUILD_HALL_TIER_CAGE])).toBe(true)
  })

  it('reads progress out of the store house and never past the asking price', () => {
    const build = GUILD_HALL_TIERS[0]
    const needs = guildHallTierNeeds(build, [
      stack('ITEM-0015', 400),
      stack('ITEM-0015', 5000),
      stack('ITEM-0031', 900),
    ])
    expect(needs[0].have).toBe(5400)
    expect(needs[0].counted).toBe(1000)
    expect(needs[1].have).toBe(0)
    expect(guildHallTierMet(build, [])).toBe(false)
  })

  it('spends what a finished step asked for and leaves the rest', () => {
    const settled = settleGuildHallTiers(
      [stack('ITEM-0015', 1200), stack('ITEM-0095', 100), stack('ITEM-0031', 3)],
      [],
    )
    expect(settled.finishedNow.map((tier) => tier.id)).toEqual([GUILD_HALL_TIER_BUILD])
    expect(settled.storehouse).toEqual([stack('ITEM-0015', 200), stack('ITEM-0031', 3)])
  })

  it('will not finish a room tier until gold and materials are both in', () => {
    const materials = [
      stack('ITEM-0015', 1000),
      stack('ITEM-0095', 100),
      stack('ITEM-0017', 24_000),
      stack('ITEM-0002', 10_000),
      stack('ITEM-0006', 6_320),
    ]
    const noGold = settleGuildHallTiers(materials, [])
    expect(noGold.completedTiers).toEqual([GUILD_HALL_TIER_BUILD])
    expect(guildHallTierGoldMet(GUILD_HALL_TIERS[1], 9_999)).toBe(false)
    const withGold = settleGuildHallTiers(noGold.storehouse, noGold.completedTiers, 10_000)
    expect(withGold.completedTiers).toEqual([GUILD_HALL_TIER_BUILD, GUILD_HALL_TIER_BANK])
    expect(guildHallBankUnlocked(withGold.completedTiers)).toBe(true)
  })

  it('does not pay for a step twice', () => {
    const settled = settleGuildHallTiers([stack('ITEM-0015', 1000), stack('ITEM-0095', 100)], [
      GUILD_HALL_TIER_BUILD,
    ])
    expect(settled.finishedNow).toEqual([])
    expect(settled.storehouse).toHaveLength(2)
  })

  it('chip-ins cap at 1M and migrate old paid debt into the running total', () => {
    expect(guildHallGoldChipInCap(0)).toBe(GUILD_HALL_GOLD_CAP)
    expect(guildHallGoldChipInCap(400_000)).toBe(600_000)
    expect(guildHallGoldChipInCap(GUILD_HALL_GOLD_CAP)).toBe(0)
    expect(goldContributedFromDebtRemaining(600_000)).toBe(400_000)
    expect(goldContributedFromDebtRemaining(0)).toBe(GUILD_HALL_GOLD_CAP)
  })

  it('the next step names how much of an item it will still take', () => {
    const store = [stack('ITEM-0015', 400)]
    expect(guildHallDonationCap([], store, 'ITEM-0015')).toBe(600)
    expect(guildHallDonationCap([], store, 'ITEM-0095')).toBe(100)
    expect(guildHallDonationCap([], store, 'ITEM-0031')).toBe(0)
  })

  it('uses the listed finish lines and never the word coffer', () => {
    expect(guildHallTierFinishLine(GUILD_HALL_TIER_BANK)).toBe(
      'The counting room is open for business.',
    )
    expect(Object.values(GUILD_HALL_TIER_FINISH_LINES).join(' ')).not.toMatch(/coffer/i)
  })

  it('guild_may defaults: leader always, officers withdraw and move', () => {
    const table = defaultGuildPermissionTable()
    expect(guildMay('leader', 'withdraw', table)).toBe(true)
    expect(guildMay('officer', 'withdraw', table)).toBe(true)
    expect(guildMay('member', 'withdraw', table)).toBe(false)
    expect(guildMay('officer', 'move_up_for_grabs', table)).toBe(true)
    expect(guildMay('recruit', 'deposit', table)).toBe(true)
    expect(GUILD_BANK_TOTAL_LEVEL_REQUIRED).toBe(200)
  })

  it('merges consecutive donation batches from one player', () => {
    const first = {
      id: '1',
      guildId: 'g',
      kind: 'donation' as const,
      createdAt: 't',
      actorUserId: 'u1',
      actorUsername: 'Ada',
      role: null,
      targetUserId: null,
      targetUsername: null,
      tierId: null,
      message: '',
      gold: 50,
      items: [{ itemId: 'ITEM-0002', quantity: 10 }],
    }
    const merged = mergeGuildLogDonation(first, {
      ...first,
      gold: 25,
      items: [{ itemId: 'ITEM-0002', quantity: 5 }],
    })
    expect(merged.merged).toBe(true)
    if (merged.merged) {
      expect(merged.entry.gold).toBe(75)
      expect(merged.entry.items).toEqual([{ itemId: 'ITEM-0002', quantity: 15 }])
    }
    const other = mergeGuildLogDonation(first, { ...first, actorUserId: 'u2', gold: 1, items: [] })
    expect(other.merged).toBe(false)
  })

  it('applies a flat 5% company XP bonus', () => {
    expect(applyGuildHallCompanyXp(1000, false)).toBe(1000)
    expect(applyGuildHallCompanyXp(1000, true)).toBe(1050)
    expect(applyGuildHallCompanyXp(0, true)).toBe(0)
  })
})
