import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { addItemToInventory } from '../activity/rewards'
import { prepareDatabase } from '../data/loadDatabase'
import { equipInventoryIndex, unequipSlot } from '../equipment/loadout'
import { createNewSave } from '../save/saveStore'
import { confirmShopOffer } from '../shops/transactions'
import { toggleInventoryFavorite, isFavoriteStack } from './favorites'
import { sellInventoryIndexes } from './sell'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('inventory favorites', () => {
  it('toggles favorite, sorts favorites to the top, and blocks bag selling', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, inventory: [] }
    save = addItemToInventory(save, 'ITEM-0025', 2) // Potato
    save = addItemToInventory(save, 'ITEM-0058', 1) // Baked Potato
    expect(save.inventory.map((stack) => stack.itemId)).toEqual(['ITEM-0025', 'ITEM-0058'])

    const favorited = toggleInventoryFavorite(save, 1)
    expect(favorited).toBeTruthy()
    save = favorited!
    expect(isFavoriteStack(save.inventory[0])).toBe(true)
    expect(save.inventory[0]?.itemId).toBe('ITEM-0058')
    expect(save.inventory[1]?.itemId).toBe('ITEM-0025')

    const sold = sellInventoryIndexes(launch, save, [0])
    expect(sold.ok).toBe(false)
    if (!sold.ok) {
      expect(sold.reason).toMatch(/Favorited/i)
    }
  })

  it('keeps favorite through equip and unequip', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, inventory: [] }
    save = addItemToInventory(save, 'ITEM-0124', 1) // Wooden Sword
    const favorited = toggleInventoryFavorite(save, 0)
    expect(favorited).toBeTruthy()
    save = favorited!

    const equipped = equipInventoryIndex(launch, save, 0)
    expect(equipped.ok).toBe(true)
    if (!equipped.ok) return
    save = equipped.save
    expect(save.equipment.slots['SLOT-0001']?.favorite).toBe(true)
    expect(save.inventory.find((stack) => stack.itemId === 'ITEM-0124')).toBeUndefined()

    const unequipped = unequipSlot(save, 'SLOT-0001')
    expect(unequipped.ok).toBe(true)
    if (!unequipped.ok) return
    save = unequipped.save
    const back = save.inventory.find((stack) => stack.itemId === 'ITEM-0124')
    expect(isFavoriteStack(back)).toBe(true)
  })

  it('adds collected items onto an existing favorited stack', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, inventory: [] }
    save = addItemToInventory(save, 'ITEM-0025', 2)
    const favorited = toggleInventoryFavorite(save, 0)
    expect(favorited).toBeTruthy()
    save = favorited!

    save = addItemToInventory(save, 'ITEM-0025', 3)
    expect(save.inventory).toHaveLength(1)
    expect(save.inventory[0]?.itemId).toBe('ITEM-0025')
    expect(save.inventory[0]?.quantity).toBe(5)
    expect(isFavoriteStack(save.inventory[0])).toBe(true)
  })

  it('grows the favorited pile and leaves a leftover unfavorited pile alone', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      inventory: [
        { itemId: 'ITEM-0025', quantity: 4, favorite: true },
        { itemId: 'ITEM-0025', quantity: 2 },
      ],
    }

    save = addItemToInventory(save, 'ITEM-0025', 3)
    expect(save.inventory).toHaveLength(2)
    expect(save.inventory[0]).toMatchObject({ itemId: 'ITEM-0025', quantity: 7, favorite: true })
    expect(save.inventory[1]).toMatchObject({ itemId: 'ITEM-0025', quantity: 2 })
    expect(isFavoriteStack(save.inventory[1])).toBe(false)
  })

  it('blocks shop sells from consuming favorited stacks', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = {
      ...createNewSave(launch),
      inventory: [] as ReturnType<typeof createNewSave>['inventory'],
      currentLocationId: 'LOC-0024',
      gold: 0,
    }
    save = addItemToInventory(save, 'ITEM-0025', 3)
    const favorited = toggleInventoryFavorite(save, 0)
    expect(favorited).toBeTruthy()
    save = favorited!

    const shop = launch.Shops.find((row) => row['Internal Key'] === 'general_store')
    expect(shop).toBeTruthy()
    const result = confirmShopOffer(launch, save, shop!['Shop ID'], {
      buys: [],
      sells: [{ itemId: 'ITEM-0025', quantity: 1 }],
    })
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.reason).toMatch(/favorited/i)
    }
  })
})
