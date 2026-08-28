import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { addItemToInventory } from '../activity/rewards'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import {
  ESSENCE_ITEM_ID,
  canAccessShop,
  playerBuyPrice,
  playerSellPrice,
  shopStockEntries,
  shopStockForPlayer,
} from './shops'
import { assignRace } from '../races/assignRace'
import { confirmShopOffer } from './transactions'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('shops', () => {
  it('stocks all level-1 tools in the General Store', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const shop = launch.Shops.find((row) => row['Shop ID'] === 'SHP-0001')!
    const stock = shopStockEntries(shop).map((entry) => entry.itemId)
    expect(stock).toContain('ITEM-0102')
    expect(stock).toContain('ITEM-0108')
    expect(stock).not.toContain('ITEM-0104')
    expect(stock.length).toBeGreaterThanOrEqual(10)
    expect(playerBuyPrice(launch, shop, 'ITEM-0102')).toBe(24)
  })

  it('prices Essence at 100× base sell value in the Wizard shop', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const shop = launch.Shops.find((row) => row['Shop ID'] === 'SHP-0003')!
    expect(playerBuyPrice(launch, shop, ESSENCE_ITEM_ID)).toBe(10_000)
  })

  it('lets Dwarves access the Mining Store at Mining 35', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const shop = launch.Shops.find((row) => row['Shop ID'] === 'SHP-0002')!
    let save = createNewSave(launch)
    const dwarf = assignRace(launch, save, 'RACE-0006')
    expect(dwarf.ok).toBe(true)
    if (!dwarf.ok) return
    save = {
      ...dwarf.save,
      currentLocationId: 'LOC-0012',
      skills: dwarf.save.skills.map((skill) =>
        skill.skillId === 'SKL-0002' ? { ...skill, level: 35, xp: 50_000 } : skill,
      ),
    }
    expect(canAccessShop(launch, save, shop).ok).toBe(true)
  })

  it('buys ores at 1.5× in the Mining Store when Mining is high enough', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const shop = launch.Shops.find((row) => row['Shop ID'] === 'SHP-0002')!
    expect(playerSellPrice(launch, shop, 'ITEM-0003')).toBe(12)

    let save = createNewSave(launch)
    save = {
      ...save,
      currentLocationId: 'LOC-0012',
      gold: 0,
      skills: save.skills.map((skill) =>
        skill.skillId === 'SKL-0002' ? { ...skill, level: 40, xp: 100_000 } : skill,
      ),
    }
    save = addItemToInventory(save, 'ITEM-0003', 2)
    const result = confirmShopOffer(launch, save, 'SHP-0002', {
      buys: [],
      sells: [{ itemId: 'ITEM-0003', quantity: 2 }],
    })
    expect(result.ok).toBe(true)
    if (!result.ok) return
    expect(result.save.gold).toBe(24)
  })

  it('requires confirmation flow to buy a tool for 2× base sell value', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, gold: 24, currentLocationId: 'LOC-0024' }
    const result = confirmShopOffer(launch, save, 'SHP-0001', {
      buys: [{ itemId: 'ITEM-0102', quantity: 1 }],
      sells: [],
    })
    expect(result.ok).toBe(true)
    if (!result.ok) return
    expect(result.save.gold).toBe(0)
    expect(result.save.inventory.some((stack) => stack.itemId === 'ITEM-0102')).toBe(true)
  })

  it('allows a buy when short on gold but covered by items offered in the same trade', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const shop = launch.Shops.find((row) => row['Shop ID'] === 'SHP-0001')!
    const buyPrice = playerBuyPrice(launch, shop, 'ITEM-0102')!
    const sellPrice = playerSellPrice(launch, shop, 'ITEM-0025')!

    let save = createNewSave(launch)
    save = { ...save, gold: 0, currentLocationId: 'LOC-0024' }
    save = addItemToInventory(save, 'ITEM-0025', 5)

    const result = confirmShopOffer(launch, save, 'SHP-0001', {
      buys: [{ itemId: 'ITEM-0102', quantity: 1 }],
      sells: [{ itemId: 'ITEM-0025', quantity: 5 }],
    })
    expect(result.ok).toBe(true)
    if (!result.ok) return
    expect(result.save.gold).toBe(sellPrice * 5 - buyPrice)
    expect(result.save.inventory.some((stack) => stack.itemId === 'ITEM-0102')).toBe(true)
  })

  it('still rejects a buy when gold plus offered sells fall short', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, gold: 0, currentLocationId: 'LOC-0024' }
    save = addItemToInventory(save, 'ITEM-0025', 1)

    const result = confirmShopOffer(launch, save, 'SHP-0001', {
      buys: [{ itemId: 'ITEM-0102', quantity: 1 }],
      sells: [{ itemId: 'ITEM-0025', quantity: 1 }],
    })
    expect(result.ok).toBe(false)
  })

  it('stocks the Armory with bronze and iron swords and plate, and buys back at 1×', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const shop = launch.Shops.find((row) => row['Shop ID'] === 'SHP-0007')!
    expect(shop['Location ID']).toBe('LOC-0032')
    expect(shopStockEntries(shop).map((entry) => entry.itemId)).toEqual([
      'ITEM-0224',
      'ITEM-0228',
      'ITEM-0229',
      'ITEM-0230',
      'ITEM-0128',
      'ITEM-0155',
      'ITEM-0156',
      'ITEM-0157',
    ])
    expect(playerBuyPrice(launch, shop, 'ITEM-0224')).toBe(120)
    expect(playerSellPrice(launch, shop, 'ITEM-0224')).toBe(60)
    expect(playerSellPrice(launch, shop, 'ITEM-0128')).toBe(
      playerSellPrice(launch, launch.Shops.find((row) => row['Shop ID'] === 'SHP-0001')!, 'ITEM-0128'),
    )
  })

  it('stocks the Clothier with the tunic, specialist hats, and leather armor', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const shop = launch.Shops.find((row) => row['Shop ID'] === 'SHP-0006')!
    expect(shop['Location ID']).toBe('LOC-0029')
    const stock = shopStockEntries(shop).map((entry) => entry.itemId)
    expect(stock).toEqual([
      'ITEM-0296',
      'ITEM-0165',
      'ITEM-0166',
      'ITEM-0308',
      'ITEM-0309',
      'ITEM-0310',
      'ITEM-0311',
      'ITEM-0298',
    ])
    expect(playerBuyPrice(launch, shop, 'ITEM-0298')).toBe(56)
    expect(playerBuyPrice(launch, shop, 'ITEM-0308')).toBe(56)
    const fresh = createNewSave(launch)
    expect(shopStockForPlayer(launch, fresh, shop).map((entry) => entry.itemId)).not.toContain(
      'ITEM-0296',
    )
  })

  it("lets Helge sell ore at 2× and buy smithing work, but not ore", () => {
    const { launch } = prepareDatabase(rawDatabase)
    const shop = launch.Shops.find((row) => row['Shop ID'] === 'SHP-0008')!
    expect(shop['Location ID']).toBe('LOC-0038')
    expect(shopStockEntries(shop).map((entry) => entry.itemId)).toEqual([
      'ITEM-0003',
      'ITEM-0004',
      'ITEM-0005',
    ])
    expect(playerBuyPrice(launch, shop, 'ITEM-0003')).toBe(16)
    expect(playerSellPrice(launch, shop, 'ITEM-0003')).toBeNull()
    expect(playerSellPrice(launch, shop, 'ITEM-0077')).toBeNull()
    expect(playerSellPrice(launch, shop, 'ITEM-0128')).toBe(
      playerSellPrice(launch, launch.Shops.find((row) => row['Shop ID'] === 'SHP-0001')!, 'ITEM-0128'),
    )
  })
})
