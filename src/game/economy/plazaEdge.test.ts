import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import {
  PLAZA_SHOP_PURCHASE_RPC,
  plazaShopBuyResponseExtras,
  settlePlazaShopBuyCommand,
  type PlazaRpcAdmin,
} from '../../../supabase/functions/_shared/plaza_shop_edge.ts'
import { prepareDatabase } from '../data/loadDatabase'
import type { PlayerSave } from '../save/types'
import { createNewSave } from '../save/saveStore'
import { applyGameCommand } from '../server/authority'
import { INVENTORY_SLOT_LIMIT } from '../inventory/capacity'
import { CITADEL_PLAZA_ID } from '../world/constants'
import { HEARTHGUARD_CUIRASS_ID } from './plaza'

const rawDatabase = JSON.parse(readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'))
const START_MS = Date.parse('2026-08-13T18:00:00.000Z')
const USER_ID = 'user-plaza-edge'

function fillBag(save: PlayerSave): PlayerSave {
  const inventory = [...save.inventory]
  for (let index = 0; inventory.length < INVENTORY_SLOT_LIMIT; index += 1) {
    inventory.push({ itemId: `ITEM-FILL-${index}`, quantity: 1 })
  }
  return { ...save, inventory }
}

function recordingAdmin(answer: unknown, error: { message: string } | null = null): PlazaRpcAdmin & {
  calls: { fn: string; args: Record<string, unknown> }[]
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = []
  return {
    calls,
    rpc: async (fn, args) => {
      calls.push({ fn, args })
      return { data: answer, error }
    },
  }
}

describe('ECO-03 plaza shop through the game edge function', () => {
  const { launch } = prepareDatabase(rawDatabase)

  it('refuses plaza_shop_buy with a full bag and spends no points', () => {
    const result = applyGameCommand(rawDatabase, {
      command: 'plaza_shop_buy',
      args: { itemId: HEARTHGUARD_CUIRASS_ID },
      save: fillBag({ ...createNewSave(launch, START_MS), currentLocationId: CITADEL_PLAZA_ID, plazaPoints: 500 }),
      nowMs: START_MS,
      random: () => 0,
    })
    expect(result.ok).toBe(false)
    if (result.ok) return
    expect('save' in result).toBe(false)
    expect(result.reason).toBe(`Inventory is full (${INVENTORY_SLOT_LIMIT} slots).`)
  })

  it('makes zero plaza_shop_purchase_hosted calls when the command is refused', async () => {
    const result = applyGameCommand(rawDatabase, {
      command: 'plaza_shop_buy',
      args: { itemId: HEARTHGUARD_CUIRASS_ID },
      save: fillBag({ ...createNewSave(launch, START_MS), currentLocationId: CITADEL_PLAZA_ID, plazaPoints: 500 }),
      nowMs: START_MS,
      random: () => 0,
    })
    expect(result.ok).toBe(false)
    const admin = recordingAdmin({ ok: true, pointsSpent: 210 })
    const settled = await settlePlazaShopBuyCommand({
      commandResult: result,
      admin,
      userId: USER_ID,
      args: { itemId: HEARTHGUARD_CUIRASS_ID },
      expectedVersion: 1,
      rngState: 1,
      nowMs: START_MS,
    })
    expect(settled).toEqual({ kind: 'refused', reason: `Inventory is full (${INVENTORY_SLOT_LIMIT} slots).` })
    expect(admin.calls).toEqual([])
    expect(admin.calls.some((call) => call.fn === PLAZA_SHOP_PURCHASE_RPC)).toBe(false)
  })

  it('returns pointsSpent from the purchase RPC on a successful buy', async () => {
    const result = applyGameCommand(rawDatabase, {
      command: 'plaza_shop_buy',
      args: { itemId: HEARTHGUARD_CUIRASS_ID },
      save: {
        ...createNewSave(launch, START_MS),
        currentLocationId: CITADEL_PLAZA_ID,
        plazaPoints: 500,
      },
      nowMs: START_MS,
      random: () => 0,
    })
    expect(result.ok).toBe(true)
    if (!result.ok) return
    const admin = recordingAdmin({
      ok: true,
      version: 2,
      plazaPoints: 290,
      pointsSpent: 210,
      payload: result.save,
    })
    const settled = await settlePlazaShopBuyCommand({
      commandResult: result,
      admin,
      userId: USER_ID,
      args: { itemId: HEARTHGUARD_CUIRASS_ID },
      expectedVersion: 1,
      rngState: 1,
      nowMs: START_MS,
    })
    expect(settled.kind).toBe('purchased')
    if (settled.kind !== 'purchased') return
    expect(settled.pointsSpent).toBe(210)
    expect(settled.plazaPoints).toBe(290)
    expect(plazaShopBuyResponseExtras(settled)).toEqual({
      pointsGained: 0,
      plazaPoints: 290,
      pointsSpent: 210,
    })
    expect(admin.calls).toHaveLength(1)
    expect(admin.calls[0]?.fn).toBe(PLAZA_SHOP_PURCHASE_RPC)
    expect(admin.calls[0]?.args.p_user_id).toBe(USER_ID)
    expect(admin.calls[0]?.args.p_item_id).toBe(HEARTHGUARD_CUIRASS_ID)
  })
})
