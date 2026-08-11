import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { addItemToInventory } from '../activity/rewards'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import {
  ESSENCE_ITEM_ID,
  playerBuyPrice,
  playerSellPrice,
  shopStockEntries,
} from './shops'
import { confirmShopOffer } from './transactions'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'public/data/game-database.json'), 'utf8'),
)

describe('shops', () => {
  it('stocks all level-1 tools in the General Store', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const shop = launch.Shops.find((row) => row['Shop ID'] === 'SHP-0001')!
    const stock = shopStockEntries(shop).map((entry) => entry.itemId)
    expect(stock).toContain('ITEM-0102')
    expect(stock).toContain('ITEM-0108')
    expect(stock.length).toBeGreaterThanOrEqual(10)
    expect(playerBuyPrice(launch, shop, 'ITEM-0102')).toBe(30)
  })

  it('prices Essence at 100× base sell value in the Wizard shop', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const shop = launch.Shops.find((row) => row['Shop ID'] === 'SHP-0003')!
    expect(playerBuyPrice(launch, shop, ESSENCE_ITEM_ID)).toBe(150_000)
  })

  it('buys ores at 1.5× in the Mining Store when Mining is high enough', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const shop = launch.Shops.find((row) => row['Shop ID'] === 'SHP-0002')!
    expect(playerSellPrice(launch, shop, 'ITEM-0003')).toBe(9)

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
    expect(result.save.gold).toBe(18)
  })

  it('requires confirmation flow to buy a tool for 2× base sell value', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, gold: 30, currentLocationId: 'LOC-0024' }
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
})
