import { describe, expect, it } from 'vitest'
import type { InventoryStack } from '../save/types'
import {
  canPayGuildDebt,
  GUILD_HALL_TIERS,
  GUILD_HALL_TIER_BANK,
  GUILD_HALL_TIER_BOXING,
  GUILD_HALL_TIER_BUILD,
  guildHallBankUnlocked,
  guildHallBoxingUnlocked,
  guildHallDonationCap,
  guildHallTierMet,
  guildHallTierNeeds,
  nextGuildHallTier,
  settleGuildHallTiers,
} from './hall'

function stack(itemId: string, quantity: number): InventoryStack {
  return { itemId, quantity }
}

describe('guild hall tiers', () => {
  it('recruits cannot pay the hall debt; member and above can', () => {
    expect(canPayGuildDebt('recruit')).toBe(false)
    expect(canPayGuildDebt('member')).toBe(true)
    expect(canPayGuildDebt('leader')).toBe(true)
  })

  it('is built in three steps, in order', () => {
    expect(GUILD_HALL_TIERS.map((tier) => tier.id)).toEqual([
      GUILD_HALL_TIER_BUILD,
      GUILD_HALL_TIER_BANK,
      GUILD_HALL_TIER_BOXING,
    ])
    expect(nextGuildHallTier([])?.id).toBe(GUILD_HALL_TIER_BUILD)
    expect(nextGuildHallTier([GUILD_HALL_TIER_BUILD])?.id).toBe(GUILD_HALL_TIER_BANK)
    expect(
      nextGuildHallTier([GUILD_HALL_TIER_BUILD, GUILD_HALL_TIER_BANK, GUILD_HALL_TIER_BOXING]),
    ).toBeNull()
  })

  it('asks for cedar logs and plant fibre first, and opens nothing for them', () => {
    const build = GUILD_HALL_TIERS[0]
    expect(build.unlock).toBeUndefined()
    expect(build.cost).toEqual([
      { itemId: 'ITEM-0015', quantity: 1000 },
      { itemId: 'ITEM-0095', quantity: 100 },
    ])
  })

  it('opens the bank on the second step and the ring on the third', () => {
    expect(guildHallBankUnlocked([GUILD_HALL_TIER_BUILD])).toBe(false)
    expect(guildHallBankUnlocked([GUILD_HALL_TIER_BANK])).toBe(true)
    expect(guildHallBoxingUnlocked([GUILD_HALL_TIER_BANK])).toBe(false)
    expect(guildHallBoxingUnlocked([GUILD_HALL_TIER_BOXING])).toBe(true)
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

  it('lets one large donation finish more than one step', () => {
    const settled = settleGuildHallTiers(
      [
        stack('ITEM-0015', 1000),
        stack('ITEM-0095', 400),
        stack('ITEM-0017', 1300),
        stack('ITEM-0002', 500),
        stack('ITEM-0006', 100),
      ],
      [],
    )
    expect(settled.completedTiers).toEqual([
      GUILD_HALL_TIER_BUILD,
      GUILD_HALL_TIER_BANK,
      GUILD_HALL_TIER_BOXING,
    ])
    expect(settled.storehouse).toEqual([])
  })

  it('does not pay for a step twice', () => {
    const settled = settleGuildHallTiers([stack('ITEM-0015', 1000), stack('ITEM-0095', 100)], [
      GUILD_HALL_TIER_BUILD,
    ])
    expect(settled.finishedNow).toEqual([])
    expect(settled.storehouse).toHaveLength(2)
  })

  it('the next step names how much of an item it will still take', () => {
    const store = [stack('ITEM-0015', 400)]
    expect(guildHallDonationCap([], store, 'ITEM-0015')).toBe(600)
    expect(guildHallDonationCap([], store, 'ITEM-0095')).toBe(100)
    expect(guildHallDonationCap([], store, 'ITEM-0031')).toBe(0)
    expect(
      guildHallDonationCap(
        [GUILD_HALL_TIER_BUILD, GUILD_HALL_TIER_BANK, GUILD_HALL_TIER_BOXING],
        [],
        'ITEM-0015',
      ),
    ).toBe(0)
  })
})
