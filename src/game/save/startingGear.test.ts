import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { migrateSave } from './migrations'
import { createNewSave } from './saveStore'
import { removeRetiredItems, replaceFishingNetsWithNet } from './startingGear'
import {
  RETIRED_FISHING_NET_ITEM_ID,
  SAVE_VERSION,
  STARTING_HUNTING_TOOL_ID,
  WEAPON_TOOL_SLOT_ID,
} from './types'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('fishing net retirement', () => {
  it('is no longer a content item', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(launch.Items.some((item) => item['Item ID'] === RETIRED_FISHING_NET_ITEM_ID)).toBe(false)
    expect(launch.Items.some((item) => item['Display Name'] === 'Fishing Net')).toBe(false)
    expect(launch.Equipment.some((row) => row['Item ID'] === RETIRED_FISHING_NET_ITEM_ID)).toBe(
      false,
    )
  })

  it('rewrites bag, bank, and worn copies into the regular net', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = {
      ...createNewSave(launch),
      inventory: [
        { itemId: RETIRED_FISHING_NET_ITEM_ID, quantity: 2 },
        { itemId: STARTING_HUNTING_TOOL_ID, quantity: 1 },
      ],
      bank: [{ itemId: RETIRED_FISHING_NET_ITEM_ID, quantity: 3 }],
      equipment: {
        slots: {
          ...createNewSave(launch).equipment.slots,
          [WEAPON_TOOL_SLOT_ID]: { itemId: RETIRED_FISHING_NET_ITEM_ID, quantity: 1 },
        },
      },
    }

    const next = replaceFishingNetsWithNet(save)
    expect(next.inventory).toEqual([{ itemId: STARTING_HUNTING_TOOL_ID, quantity: 3 }])
    expect(next.bank).toEqual([{ itemId: STARTING_HUNTING_TOOL_ID, quantity: 3 }])
    expect(next.equipment.slots[WEAPON_TOOL_SLOT_ID]).toEqual({
      itemId: STARTING_HUNTING_TOOL_ID,
      quantity: 1,
    })
  })

  it('migrates leftover fishing nets when loading a v32 save', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const legacy = {
      ...createNewSave(launch),
      saveVersion: 32,
      inventory: [{ itemId: RETIRED_FISHING_NET_ITEM_ID, quantity: 1, favorite: true }],
    }
    const migrated = migrateSave(legacy)
    expect(migrated.saveVersion).toBe(SAVE_VERSION)
    expect(migrated.inventory).toEqual([
      { itemId: STARTING_HUNTING_TOOL_ID, quantity: 1, favorite: true },
    ])
  })
})

describe('retired item cleanup', () => {
  it('drops leftover 325/346 stacks from bag, bank, and worn slots', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const next = removeRetiredItems({
      ...base,
      inventory: [
        { itemId: 'ITEM-0325', quantity: 2 },
        { itemId: 'ITEM-0003', quantity: 4 },
      ],
      bank: [{ itemId: 'ITEM-0346', quantity: 1 }],
      equipment: {
        slots: {
          ...base.equipment.slots,
          [WEAPON_TOOL_SLOT_ID]: { itemId: 'ITEM-0144', quantity: 1 },
        },
      },
    })
    expect(next.inventory).toEqual([{ itemId: 'ITEM-0003', quantity: 4 }])
    expect(next.bank).toEqual([])
    expect(next.equipment.slots[WEAPON_TOOL_SLOT_ID]).toBeNull()
  })

  it('migrates leftover retired stacks when loading a v45 save', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const migrated = migrateSave({
      ...createNewSave(launch),
      saveVersion: 45,
      inventory: [{ itemId: 'ITEM-0325', quantity: 1 }],
    })
    expect(migrated.saveVersion).toBe(SAVE_VERSION)
    expect(migrated.inventory).toEqual([])
  })
})
