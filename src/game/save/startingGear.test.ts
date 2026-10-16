import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { migrateSave } from './migrations'
import { createNewSave } from './saveStore'
import { removeRetiredItems, replaceFishingNetsWithNet } from './startingGear'
import {
  REMOVED_ANCIENT_BINDING_ACTION_ID,
  REMOVED_ANCIENT_BINDING_ITEM_ID,
  REMOVED_ANCIENT_BINDING_RECIPE_ID,
  REMOVED_REGULAR_BOW_ITEM_ID,
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

describe('REN-01 Regular Bow and Ancient Binding removal', () => {
  it('deletes Regular Bow and Ancient Binding from content', () => {
    const { source, launch } = prepareDatabase(rawDatabase)
    for (const db of [source, launch]) {
      expect(db.Items.some((item) => item['Item ID'] === REMOVED_REGULAR_BOW_ITEM_ID)).toBe(false)
      expect(db.Items.some((item) => item['Item ID'] === REMOVED_ANCIENT_BINDING_ITEM_ID)).toBe(false)
      expect(db.Equipment.some((row) => row['Item ID'] === REMOVED_REGULAR_BOW_ITEM_ID)).toBe(false)
      expect(db.Recipes.some((row) => row['Recipe ID'] === REMOVED_ANCIENT_BINDING_RECIPE_ID)).toBe(
        false,
      )
      expect(db.Actions.some((row) => row['Action ID'] === REMOVED_ANCIENT_BINDING_ACTION_ID)).toBe(
        false,
      )
    }
  })

  it('drops leftover copies from bag, bank, equipment, presets, mail, and queued crafts', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const migrated = migrateSave({
      ...base,
      saveVersion: 65,
      inventory: [
        { itemId: REMOVED_REGULAR_BOW_ITEM_ID, quantity: 1 },
        { itemId: 'ITEM-0003', quantity: 4 },
        { itemId: REMOVED_ANCIENT_BINDING_ITEM_ID, quantity: 2 },
      ],
      bank: [{ itemId: REMOVED_REGULAR_BOW_ITEM_ID, quantity: 3 }],
      equipment: {
        slots: {
          ...base.equipment.slots,
          [WEAPON_TOOL_SLOT_ID]: { itemId: REMOVED_REGULAR_BOW_ITEM_ID, quantity: 1 },
        },
      },
      equipmentPresets: base.equipmentPresets.map((preset, index) =>
        index === 0
          ? {
              ...preset,
              slots: {
                ...preset.slots,
                [WEAPON_TOOL_SLOT_ID]: { itemId: REMOVED_REGULAR_BOW_ITEM_ID, quantity: 1 },
              },
            }
          : preset,
      ),
      mailbox: [
        {
          id: 'mail-ren01',
          catalogId: null,
          subject: 'A bow',
          body: 'Keep this Regular Bow.',
          sentAt: '2026-01-01T00:00:00.000Z',
          readAt: null,
          attachments: [{ itemId: REMOVED_REGULAR_BOW_ITEM_ID, quantity: 1 }],
          claimedAt: null,
        },
      ],
      productionRecipeId: REMOVED_ANCIENT_BINDING_RECIPE_ID,
      productionQuantityTotal: 1,
      productionQuantityRemaining: 1,
      currentActionId: REMOVED_ANCIENT_BINDING_ACTION_ID,
      currentActivityId: 'ACT-0001',
      actionStartedAt: '2026-01-01T00:00:00.000Z',
      actionDurationMs: 12000,
      activityStartedAt: '2026-01-01T00:00:00.000Z',
      heldActionByActivityId: { 'ACT-0001': REMOVED_ANCIENT_BINDING_ACTION_ID },
      activityTransition: {
        kind: 'starting',
        activityId: 'ACT-0001',
        followUpActivityId: null,
        productionRecipeId: REMOVED_ANCIENT_BINDING_RECIPE_ID,
        productionQuantity: 1,
        startedAt: '2026-01-01T00:00:00.000Z',
        durationMs: 1000,
      },
    })

    expect(migrated.saveVersion).toBe(SAVE_VERSION)
    expect(migrated.inventory).toEqual([{ itemId: 'ITEM-0003', quantity: 4 }])
    expect(migrated.bank).toEqual([])
    expect(migrated.equipment.slots[WEAPON_TOOL_SLOT_ID]).toBeNull()
    expect(migrated.equipmentPresets[0]?.slots[WEAPON_TOOL_SLOT_ID]).toBeNull()
    expect(migrated.mailbox[0]?.body).toBe('Keep this Regular Bow.')
    expect(migrated.mailbox[0]?.attachments).toEqual([])
    expect(migrated.productionRecipeId).toBeNull()
    expect(migrated.productionQuantityTotal).toBeNull()
    expect(migrated.productionQuantityRemaining).toBeNull()
    expect(migrated.currentActionId).toBeNull()
    expect(migrated.currentActivityId).toBeNull()
    expect(migrated.activityTransition).toBeNull()
    expect(migrated.heldActionByActivityId).toEqual({})
  })
})
