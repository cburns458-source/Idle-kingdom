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
const LEATHER_HELMET_ID = 'ITEM-0308'
const HELMET_SLOT_ID = 'SLOT-0003'
const GLOVES_SLOT_ID = 'SLOT-0007'

describe('clothes', () => {
  it('sells the tunic, specialist hats, leather armor, mitts, and scythe at the Citadel clothier', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const shop = launch.Shops.find((row) => row['Shop ID'] === 'SHP-0006')
    expect(shop?.['Location ID']).toBe('LOC-0029')
    expect(shopStockEntries(shop!).map((entry) => entry.itemId)).toEqual([
      'ITEM-0296',
      CHEF_HAT_ID,
      WIZARD_HAT_ID,
      'ITEM-0308',
      'ITEM-0309',
      'ITEM-0310',
      'ITEM-0311',
      LEATHER_GLOVES_ID,
      'ITEM-0316',
      'ITEM-0317',
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

  it('lets a new character wear a Leather Helmet', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = { ...createNewSave(launch), inventory: [] as { itemId: string; quantity: number }[] }
    save = addItemToInventory(save, LEATHER_HELMET_ID, 1)
    const helmet = equipItemFromInventory(launch, save, LEATHER_HELMET_ID)
    expect(helmet.ok).toBe(true)
    if (!helmet.ok) return
    expect(helmet.save.equipment.slots[HELMET_SLOT_ID]?.itemId).toBe(LEATHER_HELMET_ID)
  })

  it('gives leather armor half of bronze health and no damage reduction', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const byItem = Object.fromEntries(
      launch.Equipment.map((row) => [row['Item ID'], row] as const),
    )
    expect(byItem[LEATHER_HELMET_ID]?.['HP Bonus']).toBe(15)
    expect(byItem[LEATHER_HELMET_ID]?.['Damage Reduction']).toBe(0)
    expect(byItem['ITEM-0309']?.['HP Bonus']).toBe(35)
    expect(byItem['ITEM-0309']?.['Damage Reduction']).toBe(0)
    expect(byItem['ITEM-0310']?.['HP Bonus']).toBe(25)
    expect(byItem['ITEM-0311']?.['HP Bonus']).toBe(15)
    expect(byItem[LEATHER_GLOVES_ID]?.['HP Bonus']).toBe(10)
    expect(byItem[LEATHER_GLOVES_ID]?.['Damage Reduction']).toBe(0)

    const gloves = launch.Projects.find((row) => row['Project ID'] === 'PRJ-0152')
    expect(gloves?.['XP Reward']).toBe(750)
    expect(gloves?.['Input 1 Item ID']).toBe('ITEM-0045')
    expect(gloves?.['Input 1 Quantity']).toBe(5)
    expect(gloves?.['Input 2 Item ID']).toBe('ITEM-0095')
    expect(gloves?.['Required Skill 1 Level']).toBe(1)
    expect(launch.Items.find((row) => row['Item ID'] === LEATHER_GLOVES_ID)?.['Base Sell Value']).toBe(
      28,
    )
  })
})
