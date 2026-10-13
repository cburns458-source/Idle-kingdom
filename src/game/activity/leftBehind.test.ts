import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { applyCombatVictory } from '../combat/engine'
import { INVENTORY_SLOT_LIMIT } from '../inventory/capacity'
import { createNewSave } from '../save/saveStore'
import type { PlayerSave } from '../save/types'
import { completeGatheringAction } from './engine'
import { resolveActionRewards } from './rewards'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

function seqRandom(values: number[]): () => number {
  let i = 0
  return () => values[Math.min(i++, values.length - 1)]!
}

function fullBag(save: PlayerSave): PlayerSave {
  return {
    ...save,
    inventory: Array.from({ length: INVENTORY_SLOT_LIMIT }, (_, index) => ({
      itemId: `FILL-${index}`,
      quantity: 1,
    })),
  }
}

describe('bag-full left-behind reporting', () => {
  it('reports gathering drops that do not fit and does not add them', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = fullBag({ ...createNewSave(launch), inventory: [] })
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0035')!
    // Hit the 75% potato drop, pick the only entry, miss the 0.5% secondary.
    const rewarded = resolveActionRewards(launch, save, action, seqRandom([0, 0, 1]))
    expect(rewarded.loot).toEqual([])
    expect(rewarded.leftBehind).toEqual([
      expect.objectContaining({ itemId: 'ITEM-0025', quantity: 1 }),
    ])
    expect(rewarded.save.inventory).toHaveLength(INVENTORY_SLOT_LIMIT)
    expect(rewarded.save.inventory.some((stack) => stack.itemId === 'ITEM-0025')).toBe(false)
  })

  it('still grows an existing stack when the bag is full', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = {
      ...createNewSave(launch),
      inventory: [
        { itemId: 'ITEM-0025', quantity: 2 },
        ...Array.from({ length: INVENTORY_SLOT_LIMIT - 1 }, (_, index) => ({
          itemId: `FILL-${index}`,
          quantity: 1,
        })),
      ],
    }
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0035')!
    const rewarded = resolveActionRewards(launch, save, action, seqRandom([0, 0, 1]))
    expect(rewarded.leftBehind).toEqual([])
    expect(rewarded.loot).toEqual([
      expect.objectContaining({ itemId: 'ITEM-0025', quantity: 1 }),
    ])
    expect(rewarded.save.inventory.find((stack) => stack.itemId === 'ITEM-0025')?.quantity).toBe(3)
  })

  it('threads left-behind through a completed gathering action', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = fullBag({ ...createNewSave(launch), inventory: [] })
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0035')!
    const completed = completeGatheringAction(launch, save, action, seqRandom([0, 0, 0, 1]))
    expect(completed.result.loot).toEqual([])
    expect(completed.result.leftBehind).toEqual([
      expect.objectContaining({ itemId: 'ITEM-0025', quantity: 1 }),
    ])
    expect(completed.save.inventory.some((stack) => stack.itemId === 'ITEM-0025')).toBe(false)
  })

  it('reports combat drops that do not fit and does not add them', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = fullBag(createNewSave(launch))
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0001')!
    const enemy = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0001')!
    const victory = applyCombatVictory(launch, save, action, enemy, () => 0)
    expect(victory.loot).toEqual([])
    expect(victory.leftBehind).toEqual([
      expect.objectContaining({ itemId: 'ITEM-0054', quantity: 1 }),
    ])
    expect(victory.save.inventory).toHaveLength(INVENTORY_SLOT_LIMIT)
    expect(victory.save.inventory.some((stack) => stack.itemId === 'ITEM-0054')).toBe(false)
  })
})
