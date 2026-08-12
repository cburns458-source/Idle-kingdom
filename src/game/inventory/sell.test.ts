import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { addItemToInventory } from '../activity/rewards'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { fieldSellPrice, sellInventoryIndexes, sellPriceAtLocation } from './sell'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('inventory selling', () => {
  it('pays 50% of base sell value when no shop is at the location', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = { ...createNewSave(launch), currentLocationId: 'LOC-0009' }
    save = addItemToInventory(save, 'ITEM-0025', 4)
    const baseField = fieldSellPrice(launch, 'ITEM-0025')
    expect(baseField).toBeTruthy()
    const priced = sellPriceAtLocation(launch, save, 'ITEM-0025')
    expect(priced?.shopId).toBeNull()
    expect(priced?.unitPrice).toBe(baseField)

    const sold = sellInventoryIndexes(launch, save, [save.inventory.length - 1])
    expect(sold.ok).toBe(true)
    if (!sold.ok) return
    expect(sold.goldEarned).toBe((baseField ?? 0) * 4)
    expect(sold.save.inventory.some((stack) => stack.itemId === 'ITEM-0025')).toBe(false)
  })

  it('uses shop sell price when an accessible shop will buy the item', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = { ...createNewSave(launch), currentLocationId: 'LOC-0024' }
    save = addItemToInventory(save, 'ITEM-0025', 2)
    const priced = sellPriceAtLocation(launch, save, 'ITEM-0025')
    expect(priced?.shopId).toBeTruthy()
    expect(priced?.unitPrice).toBeGreaterThan(fieldSellPrice(launch, 'ITEM-0025') ?? 0)
  })
})
