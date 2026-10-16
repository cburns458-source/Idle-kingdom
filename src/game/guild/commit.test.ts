import { describe, expect, it } from 'vitest'
import { emptyGuildHallState } from './economy'
import {
  commitGuildHallFromPlayerSaves,
  goldTakenFromPlayerSaves,
} from './commit'
import {
  GUILD_HALL_GOLD_CAP,
  GUILD_HALL_TIER_ARCANA,
  GUILD_HALL_TIER_BANK,
  GUILD_HALL_TIER_BOXING,
  GUILD_HALL_TIER_BUILD,
  GUILD_HALL_TIER_CAGE,
  GUILD_HALL_TIER_GARDEN,
} from './hall'

const ALL_TIERS = [
  GUILD_HALL_TIER_BUILD,
  GUILD_HALL_TIER_BANK,
  GUILD_HALL_TIER_BOXING,
  GUILD_HALL_TIER_GARDEN,
  GUILD_HALL_TIER_ARCANA,
  GUILD_HALL_TIER_CAGE,
]

describe('guild hall save-delta commit', () => {
  it('credits only gold the hosted save actually lost', () => {
    expect(goldTakenFromPlayerSaves(500, 400)).toBe(100)
    expect(goldTakenFromPlayerSaves(400, 400)).toBe(0)
    expect(goldTakenFromPlayerSaves(100, 250)).toBe(0)
  })

  it('ignores a forged gold_contributed total when the save did not pay', () => {
    const committed = commitGuildHallFromPlayerSaves({
      previousGold: 500,
      nextGold: 500,
      previousInventory: [],
      nextInventory: [],
      hall: emptyGuildHallState(),
      userId: 'u1',
      proposed: {
        goldContributed: GUILD_HALL_GOLD_CAP,
        completedTiers: ALL_TIERS,
        storehouse: [],
      },
    })
    expect(committed.goldTaken).toBe(0)
    expect(committed.hall.goldContributed).toBe(0)
    expect(committed.hall.completedTiers).toEqual([])
    expect(committed.finishedNow).toEqual([])
  })

  it('adds only the gold deducted from the save, even if the payload claims the cap', () => {
    const hall = emptyGuildHallState()
    hall.goldContributed = 50
    const committed = commitGuildHallFromPlayerSaves({
      previousGold: 250,
      nextGold: 200,
      previousInventory: [],
      nextInventory: [],
      hall,
      userId: 'u1',
      proposed: { goldContributed: GUILD_HALL_GOLD_CAP },
    })
    expect(committed.goldTaken).toBe(50)
    expect(committed.hall.goldContributed).toBe(100)
    expect(committed.hall.goldContributedBy.u1).toBe(50)
  })

  it('settles Build the Hall from donated materials, not from claimed completed_tiers', () => {
    const forged = commitGuildHallFromPlayerSaves({
      previousGold: 0,
      nextGold: 0,
      previousInventory: [
        { itemId: 'ITEM-0015', quantity: 1000 },
        { itemId: 'ITEM-0095', quantity: 100 },
      ],
      nextInventory: [
        { itemId: 'ITEM-0015', quantity: 1000 },
        { itemId: 'ITEM-0095', quantity: 100 },
      ],
      hall: emptyGuildHallState(),
      userId: 'u1',
      proposed: { completedTiers: ALL_TIERS, storehouse: [] },
    })
    expect(forged.hall.completedTiers).toEqual([])
    expect(forged.hall.storehouse).toEqual([])

    const honest = commitGuildHallFromPlayerSaves({
      previousGold: 0,
      nextGold: 0,
      previousInventory: [
        { itemId: 'ITEM-0015', quantity: 1000 },
        { itemId: 'ITEM-0095', quantity: 100 },
      ],
      nextInventory: [],
      hall: emptyGuildHallState(),
      userId: 'u1',
      proposed: { completedTiers: ALL_TIERS, storehouse: [] },
    })
    expect(honest.hall.completedTiers).toEqual([GUILD_HALL_TIER_BUILD])
    expect(honest.finishedNow).toEqual([GUILD_HALL_TIER_BUILD])
    expect(honest.hall.storehouse).toEqual([])
  })

  it('does not finish Counting Room until the gold total is actually chipped in', () => {
    const materials = commitGuildHallFromPlayerSaves({
      previousGold: 10_000,
      nextGold: 10_000,
      previousInventory: [
        { itemId: 'ITEM-0015', quantity: 1000 },
        { itemId: 'ITEM-0095', quantity: 100 },
        { itemId: 'ITEM-0017', quantity: 24_000 },
        { itemId: 'ITEM-0002', quantity: 10_000 },
        { itemId: 'ITEM-0006', quantity: 6_320 },
      ],
      nextInventory: [],
      hall: emptyGuildHallState(),
      userId: 'u1',
      proposed: { goldContributed: 10_000, completedTiers: [GUILD_HALL_TIER_BUILD, GUILD_HALL_TIER_BANK] },
    })
    expect(materials.hall.goldContributed).toBe(0)
    expect(materials.hall.completedTiers).toEqual([GUILD_HALL_TIER_BUILD])
    expect(materials.hall.storehouse).toEqual([
      { itemId: 'ITEM-0017', quantity: 24_000 },
      { itemId: 'ITEM-0002', quantity: 10_000 },
      { itemId: 'ITEM-0006', quantity: 6_320 },
    ])
  })

  it('ignores extra stacks a forged storehouse tries to invent', () => {
    const committed = commitGuildHallFromPlayerSaves({
      previousGold: 0,
      nextGold: 0,
      previousInventory: [],
      nextInventory: [],
      hall: emptyGuildHallState(),
      userId: 'u1',
      proposed: {
        storehouse: [{ itemId: 'ITEM-0015', quantity: 1000 }],
        completedTiers: [GUILD_HALL_TIER_BUILD],
      },
    })
    expect(committed.hall.storehouse).toEqual([])
    expect(committed.hall.completedTiers).toEqual([])
  })
})
