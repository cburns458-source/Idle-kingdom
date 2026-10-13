import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { BOUNTY_CATALOG } from '../bounties/catalog'
import { applyBountyReward, bountyPointsFor } from '../bounties/reward'
import { prepareDatabase } from '../data/loadDatabase'
import { applyRankedPvpResult } from '../pvp/matchmaking'
import { createNewSave } from '../save/saveStore'
import { applyGameCommand } from '../server/authority'
import { confirmShopOffer } from '../shops/transactions'
import { CITADEL_PLAZA_ID } from '../world/constants'
import { payReward } from './payout'
import {
  HEARTHGUARD_CUIRASS_ID,
  HEARTHGUARD_SET_BONUS_TEXT,
  PLAZA_SHOP_INSUFFICIENT_POINTS,
  PLAZA_SHOP_STOCK,
  RANKED_PVP_WIN_POINTS,
  hearthguardSetBonusText,
  plazaPointsOf,
  purchasePlazaShopItem,
} from './plaza'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

const START_MS = Date.parse('2026-08-13T18:00:00.000Z')

describe('ECO-03 plaza points', () => {
  const { launch } = prepareDatabase(rawDatabase)

  it('ranked win grants exactly 25 points and 0 gold', () => {
    const save = createNewSave(launch, START_MS)
    const goldBefore = save.gold
    const applied = applyRankedPvpResult(save, true, START_MS)
    expect(applied.goldGained).toBe(0)
    expect(applied.pointsGained).toBe(RANKED_PVP_WIN_POINTS)
    expect(applied.pointsGained).toBe(25)
    expect(applied.save.gold).toBe(goldBefore)
    expect(plazaPointsOf(applied.save)).toBe(25)
  })

  it('bounty points round down', () => {
    const save = createNewSave(launch, START_MS)
    const bounty = {
      id: 'BNT-TEST-FRACTION',
      title: 'Fraction',
      description: 'Round down.',
      kind: 'defeat' as const,
      targetId: 'ENM-0001',
      amount: 1,
      rewardGold: 40.9,
      firstPlaceBonusGold: 0.8,
    }
    expect(bountyPointsFor(bounty, true)).toBe(41)
    expect(bountyPointsFor(bounty, false)).toBe(40)
    const first = applyBountyReward(save, bounty, true)
    expect(first.goldGained).toBe(0)
    expect(first.pointsGained).toBe(41)
    expect(plazaPointsOf(first.save)).toBe(41)
    expect(first.save.gold).toBe(save.gold)
    const paid = payReward(save, { type: 'plaza_points', amount: 12.7 })
    expect(paid.paid).toBe(12)
    expect(plazaPointsOf(paid.save)).toBe(12)
  })

  it('shop purchase with insufficient points is refused and nothing deducted', () => {
    const save = {
      ...createNewSave(launch, START_MS),
      currentLocationId: CITADEL_PLAZA_ID,
      plazaPoints: 209,
    }
    const goldBefore = save.gold
    const result = purchasePlazaShopItem(launch, save, HEARTHGUARD_CUIRASS_ID, 1)
    expect(result.ok).toBe(false)
    if (result.ok) return
    expect(result.reason).toBe(PLAZA_SHOP_INSUFFICIENT_POINTS)
    expect(plazaPointsOf(save)).toBe(209)
    expect(save.gold).toBe(goldBefore)
    expect(save.inventory.some((stack) => stack.itemId === HEARTHGUARD_CUIRASS_ID)).toBe(false)
  })

  it('client-supplied amounts are ignored', () => {
    const atPlaza = {
      ...createNewSave(launch, START_MS),
      currentLocationId: CITADEL_PLAZA_ID,
      plazaPoints: 210,
    }
    const cheap = purchasePlazaShopItem(launch, atPlaza, HEARTHGUARD_CUIRASS_ID, 1)
    expect(cheap.ok).toBe(true)
    if (!cheap.ok) return
    expect(cheap.pointsSpent).toBe(210)
    expect(cheap.plazaPoints).toBe(0)
    expect(plazaPointsOf(cheap.save)).toBe(0)

    const them = { ...createNewSave(launch, START_MS), currentHp: 1 }
    const faked = applyGameCommand(rawDatabase, {
      command: 'ranked_pvp_fight',
      args: { won: true, pointsGained: 999, goldGained: 5000, amount: 999 },
      save: createNewSave(launch, START_MS),
      nowMs: START_MS,
      random: () => 0,
      opponentSave: them,
      issuedFightId: 'fight-ignore-amounts',
    })
    expect(faked.ok).toBe(false)
    if (!faked.ok) expect(faked.reason).toBe('The server resolves ranked fights.')

    const honest = applyGameCommand(rawDatabase, {
      command: 'ranked_pvp_fight',
      args: { pointsGained: 999, goldGained: 5000, amount: 1 },
      save: createNewSave(launch, START_MS),
      nowMs: START_MS,
      random: () => 0,
      opponentSave: them,
      issuedFightId: 'fight-honest',
    })
    expect(honest.ok).toBe(true)
    if (!honest.ok) return
    expect(honest.goldGained).toBe(0)
    if (honest.pvpOutcome === 'win') {
      expect(honest.pointsGained).toBe(25)
      expect(plazaPointsOf(honest.save)).toBe(25)
    } else {
      expect(honest.pointsGained).toBe(0)
      expect(plazaPointsOf(honest.save)).toBe(0)
    }
    expect(honest.save.gold).toBe(0)
  })

  it('refuses gold shop_confirm for the Hearthguard shop', () => {
    const save = {
      ...createNewSave(launch, START_MS),
      currentLocationId: CITADEL_PLAZA_ID,
      gold: 10_000,
    }
    const result = confirmShopOffer(
      launch,
      save,
      'SHP-0011',
      { buys: [{ itemId: HEARTHGUARD_CUIRASS_ID, quantity: 1 }], sells: [] },
      START_MS,
    )
    expect(result.ok).toBe(false)
    if (!result.ok) expect(result.reason).toBe('Buy this with plaza points.')
    expect(save.gold).toBe(10_000)
    expect(save.inventory.some((stack) => stack.itemId === HEARTHGUARD_CUIRASS_ID)).toBe(false)
  })

  it('prints the Hearthguard set bonus only at 5/5', () => {
    const save = createNewSave(launch, START_MS)
    expect(hearthguardSetBonusText(save)).toBeNull()
    const worn = {
      ...save,
      equipment: {
        slots: {
          ...save.equipment.slots,
          'SLOT-0003': { itemId: 'ITEM-0427', quantity: 1 },
          'SLOT-0004': { itemId: 'ITEM-0428', quantity: 1 },
          'SLOT-0005': { itemId: 'ITEM-0429', quantity: 1 },
          'SLOT-0007': { itemId: 'ITEM-0430', quantity: 1 },
          'SLOT-0006': { itemId: 'ITEM-0431', quantity: 1 },
        },
      },
    }
    expect(hearthguardSetBonusText(worn)).toBe(HEARTHGUARD_SET_BONUS_TEXT)
    expect(HEARTHGUARD_SET_BONUS_TEXT).toBe('Hearthguard (5/5): +10% max HP.')
  })

  it('returns pointsSpent on plaza_shop_buy', () => {
    const result = applyGameCommand(rawDatabase, {
      command: 'plaza_shop_buy',
      args: { itemId: HEARTHGUARD_CUIRASS_ID, points: 1 },
      save: {
        ...createNewSave(launch, START_MS),
        currentLocationId: CITADEL_PLAZA_ID,
        plazaPoints: 210,
      },
      nowMs: START_MS,
      random: () => 0,
    })
    expect(result.ok).toBe(true)
    if (!result.ok) return
    expect(result.pointsSpent).toBe(210)
    expect(result.plazaPoints).toBe(0)
    expect(result.pointsGained).toBe(0)
  })

  it('SQL bounty points and plaza shop prices match the TS catalog', () => {
    const sql = readFileSync(
      resolve(process.cwd(), 'supabase/migrations/20261013200000_eco03_plaza_points_payouts.sql'),
      'utf8',
    )
    const bountyFn = functionBody(sql, 'bounty_plaza_points')
    const baseMap = whenThenMap(sliceBetween(bountyFn, 'v_base :=', 'v_bonus :='))
    const bonusMap = whenThenMap(sliceBetween(bountyFn, 'v_bonus :=', 'return floor'))
    expect(Object.keys(baseMap).sort()).toEqual(BOUNTY_CATALOG.map((row) => row.id).sort())
    for (const bounty of BOUNTY_CATALOG) {
      expect(baseMap[bounty.id], bounty.id).toBe(bounty.rewardGold)
      expect(bonusMap[bounty.id], `${bounty.id} first`).toBe(bounty.firstPlaceBonusGold)
    }

    const priceMap = whenThenMap(functionBody(sql, 'plaza_shop_item_price'))
    expect(Object.keys(priceMap).sort()).toEqual(PLAZA_SHOP_STOCK.map((row) => row.itemId).sort())
    for (const row of PLAZA_SHOP_STOCK) {
      expect(priceMap[row.itemId], row.itemId).toBe(row.points)
    }
  })
})

function functionBody(sql: string, name: string): string {
  const start = sql.indexOf(`create or replace function public.${name}`)
  expect(start, name).toBeGreaterThanOrEqual(0)
  const next = sql.indexOf('create or replace function', start + 1)
  return next === -1 ? sql.slice(start) : sql.slice(start, next)
}

function sliceBetween(sql: string, startMarker: string, endMarker: string): string {
  const start = sql.indexOf(startMarker)
  const end = sql.indexOf(endMarker, start + startMarker.length)
  expect(start, startMarker).toBeGreaterThanOrEqual(0)
  expect(end, endMarker).toBeGreaterThanOrEqual(0)
  return sql.slice(start, end)
}

function whenThenMap(sql: string): Record<string, number> {
  const out: Record<string, number> = {}
  const re = /when '([^']+)' then (\d+)/g
  let match: RegExpExecArray | null
  while ((match = re.exec(sql))) {
    out[match[1]] = Number(match[2])
  }
  return out
}
