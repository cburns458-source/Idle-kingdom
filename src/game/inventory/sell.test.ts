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
    save = addItemToInventory(save, 'ITEM-0224', 2)
    const priced = sellPriceAtLocation(launch, save, 'ITEM-0224')
    expect(priced?.shopId).toBeTruthy()
    expect(priced?.unitPrice).toBeGreaterThan(fieldSellPrice(launch, 'ITEM-0224') ?? 0)
  })

  it('sells enchanted gear from the bag at shop or field rates', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const sword = 'ITEM-0130'
    const base = launch.Items.find((row) => row['Item ID'] === sword)!['Base Sell Value']!
    const enchantmentId = 'ENCH-0003'

    let inField = {
      ...createNewSave(launch),
      currentLocationId: 'LOC-0009',
      gold: 0,
      inventory: [{ itemId: sword, quantity: 1, enchantmentId }],
    }
    const fieldPriced = sellPriceAtLocation(launch, inField, sword, { enchantmentId })
    expect(fieldPriced?.shopId).toBeNull()
    expect(fieldPriced?.unitPrice).toBe(fieldSellPrice(launch, sword))
    const fieldSold = sellInventoryIndexes(launch, inField, [0])
    expect(fieldSold.ok).toBe(true)
    if (!fieldSold.ok) return
    expect(fieldSold.goldEarned).toBe(fieldSellPrice(launch, sword))

    let atWizard = {
      ...createNewSave(launch),
      currentLocationId: 'LOC-0007',
      gold: 0,
      inventory: [{ itemId: sword, quantity: 1, enchantmentId }],
    }
    const wizardPriced = sellPriceAtLocation(launch, atWizard, sword, { enchantmentId })
    expect(wizardPriced?.shopId).toBe('SHP-0003')
    expect(wizardPriced?.unitPrice).toBe(Math.round(base * 2))
    const wizardSold = sellInventoryIndexes(launch, atWizard, [0])
    expect(wizardSold.ok).toBe(true)
    if (!wizardSold.ok) return
    expect(wizardSold.goldEarned).toBe(Math.round(base * 2))
  })
})
