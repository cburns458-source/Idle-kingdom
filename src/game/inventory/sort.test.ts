import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import {
  GROUP_ARCANA,
  GROUP_COOKING,
  GROUP_CRAFTING,
  GROUP_HARVESTING,
  GROUP_HUNTING,
  GROUP_METALLURGY,
  GROUP_MINING,
  GROUP_SMITHING,
  GROUP_WOODCUTTING,
  InventorySorter,
} from './sort'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('inventory group sort', () => {
  const { launch } = prepareDatabase(rawDatabase)
  const sorter = new InventorySorter(launch)

  function names(itemIds: string[], mode: 'group' | 'az' | 'search' = 'group', query = '') {
    const stacks = itemIds.map((itemId) => ({ itemId }))
    return sorter.displayIndexes(stacks, mode, query).map((index) => itemIds[index])
  }

  it('pins favorites above every group', () => {
    const stacks = [
      { itemId: 'ITEM-0003' }, // Copper Ore
      { itemId: 'ITEM-0128', favorite: true }, // Iron Sword
      { itemId: 'ITEM-0074' }, // Copper Bar
    ]
    expect(sorter.displayIndexes(stacks, 'group').map((index) => stacks[index]!.itemId)).toEqual([
      'ITEM-0128',
      'ITEM-0003',
      'ITEM-0074',
    ])
    expect(sorter.displayIndexes(stacks, 'az').map((index) => stacks[index]!.itemId)).toEqual([
      'ITEM-0128',
      'ITEM-0074',
      'ITEM-0003',
    ])
  })

  it('keeps ores, bars, and swords in their skill groups', () => {
    expect(sorter.groupOf('ITEM-0003')).toBe(GROUP_MINING) // Copper Ore
    expect(sorter.groupOf('ITEM-0074')).toBe(GROUP_METALLURGY) // Copper Bar
    expect(sorter.groupOf('ITEM-0128')).toBe(GROUP_SMITHING) // Iron Sword
    expect(names(['ITEM-0128', 'ITEM-0074', 'ITEM-0003'])).toEqual([
      'ITEM-0003',
      'ITEM-0074',
      'ITEM-0128',
    ])
  })

  it('places timber with logs and pickaxes with mining', () => {
    expect(sorter.groupOf('ITEM-0015')).toBe(GROUP_WOODCUTTING) // Cedar Log
    expect(sorter.groupOf('ITEM-0214')).toBe(GROUP_WOODCUTTING) // Cedar Timber
    expect(sorter.groupOf('ITEM-0102')).toBe(GROUP_MINING) // Wooden Pickaxe
    expect(names(['ITEM-0214', 'ITEM-0015', 'ITEM-0102'])).toEqual([
      'ITEM-0102',
      'ITEM-0015',
      'ITEM-0214',
    ])
  })

  it('orders metal tiers and cook levels low to high', () => {
    expect(names(['ITEM-0005', 'ITEM-0003', 'ITEM-0004'])).toEqual([
      'ITEM-0003', // Copper Ore
      'ITEM-0004', // Tin Ore
      'ITEM-0005', // Iron Ore
    ])
    expect(sorter.groupOf('ITEM-0058')).toBe(GROUP_COOKING) // Baked Potato
    expect(sorter.groupOf('ITEM-0061')).toBe(GROUP_COOKING) // Cooked Salmon
    expect(names(['ITEM-0061', 'ITEM-0058'])).toEqual(['ITEM-0058', 'ITEM-0061'])
  })

  it('puts hunting leftovers and crafting tablets in the intended groups', () => {
    expect(sorter.groupOf('ITEM-0054')).toBe(GROUP_HUNTING) // Beef
    expect(sorter.groupOf('ITEM-0025')).toBe(GROUP_HARVESTING) // Potato
    expect(sorter.groupOf('ITEM-0099')).toBe(GROUP_ARCANA) // Spell Tablet
    expect(sorter.groupOf('ITEM-0083')).toBe(GROUP_CRAFTING) // Bowstring
  })

  it('sorts A–Z by display name and filters Search by name only', () => {
    const bag = ['ITEM-0128', 'ITEM-0003', 'ITEM-0074'] // Iron Sword, Copper Ore, Copper Bar
    expect(names(bag, 'az')).toEqual(['ITEM-0074', 'ITEM-0003', 'ITEM-0128'])
    expect(names(bag, 'search', 'copper')).toEqual(['ITEM-0003', 'ITEM-0074'])
    expect(names(bag, 'search', 'ITEM-0003')).toEqual([])
  })
})
