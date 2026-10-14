import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import type { PlayerSave } from '../save/types'
import { createNewSave } from '../save/saveStore'
import { applyGameCommand } from '../server/authority'
import { INVENTORY_SLOT_LIMIT } from '../inventory/capacity'
import { CITADEL_PLAZA_ID } from '../world/constants'
import { HEARTHGUARD_CUIRASS_ID, plazaPointsOf } from './plaza'

const rawDatabase = JSON.parse(readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'))
const edgeSource = readFileSync(resolve(process.cwd(), 'supabase/functions/game/index.ts'), 'utf8')
const START_MS = Date.parse('2026-08-13T18:00:00.000Z')

function fillBag(save: PlayerSave): PlayerSave {
  const inventory = [...save.inventory]
  for (let index = 0; inventory.length < INVENTORY_SLOT_LIMIT; index += 1) {
    inventory.push({ itemId: `ITEM-FILL-${index}`, quantity: 1 })
  }
  return { ...save, inventory }
}

describe('ECO-03 plaza shop through the game edge function', () => {
  const { launch } = prepareDatabase(rawDatabase)

  it('refuses plaza_shop_buy with a full bag and spends no points', () => {
    const save = fillBag({ ...createNewSave(launch, START_MS), currentLocationId: CITADEL_PLAZA_ID, plazaPoints: 500 })
    const result = applyGameCommand(rawDatabase, {
      command: 'plaza_shop_buy',
      args: { itemId: HEARTHGUARD_CUIRASS_ID },
      save,
      nowMs: START_MS,
      random: () => 0,
    })
    expect(result.ok).toBe(false)
    expect(plazaPointsOf(save)).toBe(500)
    expect(save.inventory.some((stack) => stack.itemId === HEARTHGUARD_CUIRASS_ID)).toBe(false)
  })

  it('returns before the plaza RPC when the command is refused', () => {
    const refusal = edgeSource.indexOf('if (!result.ok) {')
    const rpcCall = edgeSource.indexOf("command === 'plaza_shop_buy' && hosted")
    expect(refusal).toBeGreaterThan(-1)
    expect(rpcCall).toBeGreaterThan(refusal)
  })

  it('passes pointsSpent from the purchase RPC into the response', () => {
    const settle = edgeSource.slice(edgeSource.indexOf('async function settlePlazaShopPurchase'))
    expect(settle).toContain('pointsSpent: Number(answer.pointsSpent ?? 0)')
    const branch = edgeSource.slice(
      edgeSource.indexOf("command === 'plaza_shop_buy' && hosted"),
      edgeSource.indexOf("command === 'ranked_pvp_fight' && hosted"),
    )
    expect(branch).toContain('pointsSpent: purchased.pointsSpent')
    expect(edgeSource).toContain('...bountyExtras,')
  })
})
