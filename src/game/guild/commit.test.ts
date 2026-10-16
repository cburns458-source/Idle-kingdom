import { describe, expect, it } from 'vitest'
import {
  emptyGuildHallState,
  GUILD_HALL_GOLD_CAP_REFUSAL,
  GUILD_HALL_GOLD_OVERPAY_REFUSAL,
} from './economy'
import {
  commitGuildHallFromPlayerSaves,
  goldTakenFromPlayerSaves,
  GUILD_HALL_BANK_MISMATCH_REFUSAL,
  type GuildHallCommitResult,
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

function committedOk(result: GuildHallCommitResult) {
  expect(result.ok).toBe(true)
  if (!result.ok) throw new Error(result.reason)
  return result
}

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
    const committed = committedOk(
      commitGuildHallFromPlayerSaves({
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
      }),
    )
    expect(committed.goldTaken).toBe(0)
    expect(committed.hall.goldContributed).toBe(0)
    expect(committed.hall.completedTiers).toEqual([])
    expect(committed.finishedNow).toEqual([])
  })

  it('adds only the gold deducted from the save, even if the payload claims the cap', () => {
    const hall = emptyGuildHallState()
    hall.goldContributed = 50
    const committed = committedOk(
      commitGuildHallFromPlayerSaves({
        previousGold: 250,
        nextGold: 200,
        previousInventory: [],
        nextInventory: [],
        hall,
        userId: 'u1',
        proposed: { goldContributed: GUILD_HALL_GOLD_CAP },
      }),
    )
    expect(committed.goldTaken).toBe(50)
    expect(committed.hall.goldContributed).toBe(100)
    expect(committed.hall.goldContributedBy.u1).toBe(50)
  })

  it('settles Build the Hall from donated materials, not from claimed completed_tiers', () => {
    const forged = committedOk(
      commitGuildHallFromPlayerSaves({
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
      }),
    )
    expect(forged.hall.completedTiers).toEqual([])
    expect(forged.hall.storehouse).toEqual([])

    const honest = committedOk(
      commitGuildHallFromPlayerSaves({
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
      }),
    )
    expect(honest.hall.completedTiers).toEqual([GUILD_HALL_TIER_BUILD])
    expect(honest.finishedNow).toEqual([GUILD_HALL_TIER_BUILD])
    expect(honest.hall.storehouse).toEqual([])
  })

  it('does not finish Counting Room until the gold total is actually chipped in', () => {
    const materials = committedOk(
      commitGuildHallFromPlayerSaves({
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
      }),
    )
    expect(materials.hall.goldContributed).toBe(0)
    expect(materials.hall.completedTiers).toEqual([GUILD_HALL_TIER_BUILD])
    expect(materials.hall.storehouse).toEqual([
      { itemId: 'ITEM-0017', quantity: 24_000 },
      { itemId: 'ITEM-0002', quantity: 10_000 },
      { itemId: 'ITEM-0006', quantity: 6_320 },
    ])
  })

  it('ignores extra stacks a forged storehouse tries to invent', () => {
    const committed = committedOk(
      commitGuildHallFromPlayerSaves({
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
      }),
    )
    expect(committed.hall.storehouse).toEqual([])
    expect(committed.hall.completedTiers).toEqual([])
  })

  it('does not treat catch-up ore, food, arrows, or gold as hall credit', () => {
    const hostedInventory = [
      { itemId: 'ITEM-0003', quantity: 10 },
      { itemId: 'ITEM-0058', quantity: 5 },
      { itemId: 'ITEM-ARROWS', quantity: 8 },
      { itemId: 'ITEM-0015', quantity: 3 },
    ]
    const caughtUpInventory = [
      { itemId: 'ITEM-0003', quantity: 7 },
      { itemId: 'ITEM-0058', quantity: 3 },
      { itemId: 'ITEM-ARROWS', quantity: 5 },
      { itemId: 'ITEM-0015', quantity: 3 },
    ]
    const afterInventory = [
      { itemId: 'ITEM-0003', quantity: 7 },
      { itemId: 'ITEM-0058', quantity: 3 },
      { itemId: 'ITEM-ARROWS', quantity: 5 },
      { itemId: 'ITEM-0015', quantity: 2 },
    ]
    const naive = committedOk(
      commitGuildHallFromPlayerSaves({
        previousGold: 100,
        nextGold: 90,
        previousInventory: hostedInventory,
        nextInventory: afterInventory,
        hall: emptyGuildHallState(),
        userId: 'u1',
      }),
    )
    expect(naive.goldTaken).toBe(10)
    expect(naive.hall.storehouse).toEqual([
      { itemId: 'ITEM-0003', quantity: 3 },
      { itemId: 'ITEM-0058', quantity: 2 },
      { itemId: 'ITEM-ARROWS', quantity: 3 },
      { itemId: 'ITEM-0015', quantity: 1 },
    ])

    const fromCaughtUp = committedOk(
      commitGuildHallFromPlayerSaves({
        previousGold: 130,
        nextGold: 90,
        previousInventory: caughtUpInventory,
        nextInventory: afterInventory,
        hall: emptyGuildHallState(),
        userId: 'u1',
      }),
    )
    expect(fromCaughtUp.goldTaken).toBe(40)
    expect(fromCaughtUp.hall.storehouse).toEqual([{ itemId: 'ITEM-0015', quantity: 1 }])
  })

  it('refuses gold past the cap instead of truncating it', () => {
    const hall = emptyGuildHallState()
    hall.goldContributed = 999_900
    const overpay = commitGuildHallFromPlayerSaves({
      previousGold: 500,
      nextGold: 200,
      previousInventory: [],
      nextInventory: [],
      hall,
      userId: 'u1',
    })
    expect(overpay).toEqual({ ok: false, reason: GUILD_HALL_GOLD_OVERPAY_REFUSAL })

    hall.goldContributed = GUILD_HALL_GOLD_CAP
    const atCap = commitGuildHallFromPlayerSaves({
      previousGold: 80,
      nextGold: 70,
      previousInventory: [],
      nextInventory: [],
      hall,
      userId: 'u1',
    })
    expect(atCap).toEqual({ ok: false, reason: GUILD_HALL_GOLD_CAP_REFUSAL })
  })

  it('refuses a bank change that does not match the save', () => {
    const refused = commitGuildHallFromPlayerSaves({
      previousGold: 40,
      nextGold: 40,
      previousInventory: [{ itemId: 'ITEM-0015', quantity: 5 }],
      nextInventory: [{ itemId: 'ITEM-0015', quantity: 5 }],
      previousBankItems: [],
      hall: emptyGuildHallState(),
      userId: 'u1',
      proposed: { bankItems: [{ itemId: 'ITEM-0015', quantity: 1 }] },
    })
    expect(refused).toEqual({ ok: false, reason: GUILD_HALL_BANK_MISMATCH_REFUSAL })
  })
})
