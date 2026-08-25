import { describe, expect, it } from 'vitest'
import { createNewSave } from '../save/saveStore'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { prepareDatabase } from '../data/loadDatabase'
import { addItemToInventory, addItemToInventoryExact, addItemsToInventory } from '../activity/rewards'
import { GOLD_ITEM_ID } from './gold'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('gold currency item', () => {
  it('converts Gold items into the player gold balance instead of bag slots', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const startedGold = save.gold

    const next = addItemToInventory(save, GOLD_ITEM_ID, 250)
    expect(next.gold).toBe(startedGold + 250)
    expect(next.inventory.some((stack) => stack.itemId === GOLD_ITEM_ID)).toBe(false)

    const exact = addItemToInventoryExact(save, GOLD_ITEM_ID, 10)
    expect(exact.ok).toBe(true)
    if (!exact.ok) return
    expect(exact.save.gold).toBe(startedGold + 10)
    expect(exact.save.inventory).toEqual(save.inventory)

    const partial = addItemsToInventory(save, GOLD_ITEM_ID, 5)
    expect(partial.added).toBe(5)
    expect(partial.save.gold).toBe(startedGold + 5)
  })

  it('converts the Config currency item even when it is not ITEM-0001', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const db = {
      ...launch,
      Config: launch.Config.map((row) =>
        row.Key === 'currency_item_id' ? { ...row, Value: 'ITEM-9999' } : row,
      ),
    }
    const save = createNewSave(db)
    const next = addItemToInventory(save, 'ITEM-9999', 40, null, false, db)
    expect(next.gold).toBe(save.gold + 40)
    expect(next.inventory.some((stack) => stack.itemId === 'ITEM-9999')).toBe(false)
  })
})
