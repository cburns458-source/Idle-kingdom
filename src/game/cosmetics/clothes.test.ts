import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { addItemToInventory } from '../activity/rewards'
import { prepareDatabase } from '../data/loadDatabase'
import { equipItemFromInventory } from '../equipment/loadout'
import { createNewSave } from '../save/saveStore'
import { shopStockEntries } from '../shops/shops'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

const CHEF_HAT_ID = 'ITEM-0165'
const WIZARD_HAT_ID = 'ITEM-0166'
const LEATHER_GLOVES_ID = 'ITEM-0298'
const HELMET_SLOT_ID = 'SLOT-0003'
const GLOVES_SLOT_ID = 'SLOT-0007'

describe('clothes', () => {
  it('sells the tunic, specialist hats, and Leather Gloves at the Citadel clothier', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const shop = launch.Shops.find((row) => row['Shop ID'] === 'SHP-0006')
    expect(shop?.['Location ID']).toBe('LOC-0029')
    expect(shopStockEntries(shop!).map((entry) => entry.itemId)).toEqual([
      'ITEM-0296',
      CHEF_HAT_ID,
      WIZARD_HAT_ID,
      LEATHER_GLOVES_ID,
    ])
  })

  it('lets a new character wear Leather Gloves and the specialist hats', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = { ...createNewSave(launch), inventory: [] as { itemId: string; quantity: number }[] }
    save = addItemToInventory(save, LEATHER_GLOVES_ID, 1)
    save = addItemToInventory(save, CHEF_HAT_ID, 1)

    const gloves = equipItemFromInventory(launch, save, LEATHER_GLOVES_ID)
    expect(gloves.ok).toBe(true)
    if (!gloves.ok) return
    expect(gloves.save.equipment.slots[GLOVES_SLOT_ID]?.itemId).toBe(LEATHER_GLOVES_ID)

    const hat = equipItemFromInventory(launch, gloves.save, CHEF_HAT_ID)
    expect(hat.ok).toBe(true)
    if (!hat.ok) return
    expect(hat.save.equipment.slots[HELMET_SLOT_ID]?.itemId).toBe(CHEF_HAT_ID)

    const wizardSave = addItemToInventory({ ...createNewSave(launch), inventory: [] }, WIZARD_HAT_ID, 1)
    const wizard = equipItemFromInventory(launch, wizardSave, WIZARD_HAT_ID)
    expect(wizard.ok).toBe(true)
    if (!wizard.ok) return
    expect(wizard.save.equipment.slots[HELMET_SLOT_ID]?.itemId).toBe(WIZARD_HAT_ID)
  })
})
