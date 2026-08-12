import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { equipItemFromInventory } from '../equipment/loadout'
import { createNewSave } from '../save/saveStore'
import { addItemToInventory, resolveActionRewards } from './rewards'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

function seqRandom(values: number[]): () => number {
  let i = 0
  return () => values[Math.min(i++, values.length - 1)]!
}

describe('Abundance Spell drop doubling', () => {
  it('doubles item quantity on a successful drop when the chance roll succeeds', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, inventory: [] }
    save = addItemToInventory(save, 'ITEM-0297', 1)
    const equipped = equipItemFromInventory(launch, save, 'ITEM-0297')
    expect(equipped.ok).toBe(true)
    if (!equipped.ok) return
    save = equipped.save

    // Harvest potato — 100% drop, single ITEM-0025 ×1 entry (primary table).
    // Secondary tables use the same rollTable path.
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0035')!
    // drop ok, weighted pick, abundance double (random < 0.10)
    const doubled = resolveActionRewards(launch, save, action, seqRandom([0, 0, 0.05]))
    expect(doubled.loot).toEqual([
      expect.objectContaining({ itemId: 'ITEM-0025', quantity: 2 }),
    ])

    const single = resolveActionRewards(launch, save, action, seqRandom([0, 0, 0.5]))
    expect(single.loot).toEqual([
      expect.objectContaining({ itemId: 'ITEM-0025', quantity: 1 }),
    ])
  })
})
