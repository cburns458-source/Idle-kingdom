import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { addItemToInventory } from '../activity/rewards'
import { createNewSave } from '../save/saveStore'
import { migrateSave } from '../save/migrations'
import { SAVE_VERSION, type PlayerSave } from '../save/types'
import { tryConsumeFoodAfterVictory } from '../combat/food'
import { gatheringDurationMs } from '../activity/gathering'
import {
  equipInventoryIndex,
  equipItemFromInventory,
  equipStackToSlot,
  FOOD_SLOT_ID,
  OFFHAND_SLOT_ID,
  POTION_SLOT_ID,
  unequipSlot,
  WEAPON_TOOL_SLOT_ID,
} from './loadout'
import { withRecalculatedVitals } from './vitals'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('equipment loadout', () => {
  it('moves the entire food stack out of inventory into the food slot', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, inventory: [] }
    save = addItemToInventory(save, 'ITEM-0058', 5)
    const equipped = equipItemFromInventory(launch, save, 'ITEM-0058')
    expect(equipped.ok).toBe(true)
    if (!equipped.ok) return

    expect(equipped.save.inventory.find((stack) => stack.itemId === 'ITEM-0058')).toBeUndefined()
    expect(equipped.save.equipment.slots[FOOD_SLOT_ID]).toEqual({
      itemId: 'ITEM-0058',
      quantity: 5,
    })
  })

  it('consumes from the equipped food stack across multiple victories', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, inventory: [] }
    save = equipStackToSlot(save, FOOD_SLOT_ID, 'ITEM-0058', 3)
    save = { ...save, currentHp: 900 }

    const first = tryConsumeFoodAfterVictory(launch, save)
    expect(first.consumed).toBe(true)
    expect(first.save.equipment.slots[FOOD_SLOT_ID]?.quantity).toBe(2)
    expect(first.save.inventory.find((stack) => stack.itemId === 'ITEM-0058')).toBeUndefined()

    const second = tryConsumeFoodAfterVictory(launch, { ...first.save, currentHp: 900 })
    expect(second.consumed).toBe(true)
    expect(second.save.equipment.slots[FOOD_SLOT_ID]?.quantity).toBe(1)

    const third = tryConsumeFoodAfterVictory(launch, { ...second.save, currentHp: 900 })
    expect(third.consumed).toBe(true)
    expect(third.save.equipment.slots[FOOD_SLOT_ID]).toBeNull()
  })

  it('returns the remaining food stack to inventory on unequip', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, inventory: [] }
    save = equipStackToSlot(save, FOOD_SLOT_ID, 'ITEM-0058', 4)
    const unequippedFood = unequipSlot(save, FOOD_SLOT_ID)
    expect(unequippedFood.ok).toBe(true)
    if (!unequippedFood.ok) return
    save = unequippedFood.save
    expect(save.equipment.slots[FOOD_SLOT_ID]).toBeNull()
    expect(save.inventory.find((stack) => stack.itemId === 'ITEM-0058')?.quantity).toBe(4)
  })

  it('moves the entire potion stack into the potion slot and returns it on unequip', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = addItemToInventory(save, 'ITEM-0070', 4) // Luck Potion
    const equipped = equipItemFromInventory(launch, save, 'ITEM-0070')
    expect(equipped.ok).toBe(true)
    if (!equipped.ok) return

    expect(equipped.save.inventory.find((stack) => stack.itemId === 'ITEM-0070')).toBeUndefined()
    expect(equipped.save.equipment.slots[POTION_SLOT_ID]).toEqual({
      itemId: 'ITEM-0070',
      quantity: 4,
    })

    const unequipped = unequipSlot(equipped.save, POTION_SLOT_ID)
    expect(unequipped.ok).toBe(true)
    if (!unequipped.ok) return
    expect(unequipped.save.equipment.slots[POTION_SLOT_ID]).toBeNull()
    expect(unequipped.save.inventory.find((stack) => stack.itemId === 'ITEM-0070')?.quantity).toBe(4)
  })

  it('blocks equipping gear below required skill level', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = addItemToInventory(save, 'ITEM-0119', 1) // Steel Pickaxe, Mining 35
    const result = equipItemFromInventory(launch, save, 'ITEM-0119')
    expect(result.ok).toBe(false)
    if (result.ok) return
    expect(result.reason).toMatch(/Mining level 35/i)
  })

  it('applies action time reduction from equipped tools', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    // Clear starting Net so ATR is only from pickaxe.
    const clearedNet = unequipSlot(save, 'SLOT-0001')
    expect(clearedNet.ok).toBe(true)
    if (!clearedNet.ok) return
    save = clearedNet.save
    save = addItemToInventory(save, 'ITEM-0111', 1) // Copper Pickaxe ATR 5
    const equipped = equipItemFromInventory(launch, save, 'ITEM-0111')
    expect(equipped.ok).toBe(true)
    if (!equipped.ok) return

    const digClay = launch.Actions.find((action) => action['Action ID'] === 'ACN-0019')!
    const base = Number(digClay['Base Duration Seconds'] ?? 0)
    const proficiency = Number(digClay['Proficiency Level'] ?? 1)
    const mult = 1 < proficiency ? 2 : 1
    const expected = Math.round(base * mult * 0.95 * 1000)
    expect(gatheringDurationMs(launch, equipped.save, digClay)).toBe(expected)
  })

  it('clamps current HP when max HP drops', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = {
      ...createNewSave(launch),
      currentHp: 1100,
      maxHp: 1100,
    }
    const next = withRecalculatedVitals(launch, save)
    expect(next.maxHp).toBe(1000)
    expect(next.currentHp).toBe(1000)
  })

  it('blocks unequip when the bag has no room for the returned item', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = addItemToInventory(save, 'ITEM-0111', 1) // Copper Pickaxe
    const equipped = equipItemFromInventory(launch, save, 'ITEM-0111')
    expect(equipped.ok).toBe(true)
    if (!equipped.ok) return
    save = equipped.save

    // Fill every remaining bag slot with unique, non-stacking stacks.
    const filler = Array.from({ length: 180 - save.inventory.length }, (_, i) => ({
      itemId: `FILLER-${i}`,
      quantity: 1,
    }))
    save = { ...save, inventory: [...save.inventory, ...filler] }
    expect(save.inventory).toHaveLength(180)

    const result = unequipSlot(save, 'SLOT-0001')
    expect(result.ok).toBe(false)
    if (result.ok) return
    expect(result.reason).toMatch(/space/i)
    // Nothing changed: item stays equipped, bag stays full, nothing lost.
    expect(save.equipment.slots['SLOT-0001']?.itemId).toBe('ITEM-0111')
    expect(save.inventory).toHaveLength(180)
  })

  it('still allows a like-for-like tool swap when the bag is exactly full', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = addItemToInventory(save, 'ITEM-0111', 1) // Copper Pickaxe, equip it
    const equipped = equipItemFromInventory(launch, save, 'ITEM-0111')
    expect(equipped.ok).toBe(true)
    if (!equipped.ok) return
    save = equipped.save
    save = addItemToInventory(save, 'ITEM-0102', 1) // Wooden Pickaxe (also Mining level 1)

    // Fill the bag to exactly 180 including the incoming Wooden Pickaxe stack.
    const filler = Array.from({ length: 180 - save.inventory.length }, (_, i) => ({
      itemId: `FILLER-${i}`,
      quantity: 1,
    }))
    save = { ...save, inventory: [...save.inventory, ...filler] }
    expect(save.inventory).toHaveLength(180)

    // Swapping to a different single-slot tool must not be blocked just
    // because the bag is full: removing the incoming item frees the slot
    // the outgoing item needs.
    const swapIndex = save.inventory.findIndex((stack) => stack.itemId === 'ITEM-0102')
    const result = equipInventoryIndex(launch, save, swapIndex)
    expect(result.ok).toBe(true)
    if (!result.ok) return
    expect(result.save.inventory).toHaveLength(180)
    expect(
      result.save.inventory.find((stack) => stack.itemId === 'ITEM-0111')?.quantity,
    ).toBe(1)
  })

  it('migrates v3 food item-id slots by pulling inventory into the equipped stack', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const legacy = {
      ...base,
      saveVersion: 3,
      inventory: [{ itemId: 'ITEM-0058', quantity: 5 }],
      equipment: {
        slots: {
          ...Object.fromEntries(
            Object.keys(base.equipment.slots).map((slotId) => [slotId, null as string | null]),
          ),
          [FOOD_SLOT_ID]: 'ITEM-0058',
        },
      },
    } as unknown as PlayerSave

    const migrated = migrateSave(legacy)
    expect(migrated.saveVersion).toBe(SAVE_VERSION)
    expect(migrated.bank).toEqual([])
    expect(migrated.unlockedRecipeIds).toEqual([])
    expect(migrated.activityTransition).toBeNull()
    expect(migrated.settings.showActivityRewards).toBe(true)
    expect(migrated.settings.hudShowTotalXp).toBe(false)
    expect(migrated.unlockedNpcIds).toEqual([])
    expect(migrated.unlockedLocationIds).toEqual([])
    expect(migrated.claimedMerchantTipIds).toEqual([])
    expect(migrated.critterCollections).toEqual([])
    expect(migrated.activeCritterSpawns).toEqual([])
    expect(migrated.critterProgressMs).toEqual({})
    expect(migrated.locationSearchClaims).toEqual({})
    expect(migrated.raceId).toBeNull()
    expect(migrated.cosmetics.unlocked).toEqual(['COS-0001'])
    expect(migrated.cosmetics.equipped['CSLOT-0001']).toBe('COS-0001')
    expect(migrated.cosmetics.equipped['CSLOT-0002']).toBeNull()
    expect(migrated.appearance.skinTone).toBe('APR-0001')
    expect(migrated.hasSeenWardrobeIntro).toBe(false)
    expect(typeof migrated.unattendedProgressAt).toBe('string')
    expect(migrated.activePotionEffect).toBeNull()
    expect(migrated.inventory.find((stack) => stack.itemId === 'ITEM-0058')).toBeUndefined()
    expect(migrated.equipment.slots[FOOD_SLOT_ID]).toEqual({ itemId: 'ITEM-0058', quantity: 5 })
    expect(migrated.equipment.slots['SLOT-0001']?.itemId).toBe('ITEM-0108')
    expect(migrated.productionRecipeId).toBeNull()
    expect(migrated.productionQuantityTotal).toBeNull()
    expect(migrated.productionQuantityRemaining).toBeNull()
  })

  it('equips daggers to the off-hand slot and replaces a shield', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, inventory: [] }
    save = addItemToInventory(save, 'ITEM-0145', 1) // Wooden Shield
    save = addItemToInventory(save, 'ITEM-0125', 1) // Wooden Dagger

    const shield = equipItemFromInventory(launch, save, 'ITEM-0145')
    expect(shield.ok).toBe(true)
    if (!shield.ok) return
    save = shield.save
    expect(save.equipment.slots[OFFHAND_SLOT_ID]?.itemId).toBe('ITEM-0145')

    const dagger = equipItemFromInventory(launch, save, 'ITEM-0125')
    expect(dagger.ok).toBe(true)
    if (!dagger.ok) return
    save = dagger.save
    expect(save.equipment.slots[OFFHAND_SLOT_ID]?.itemId).toBe('ITEM-0125')
    expect(save.inventory.find((stack) => stack.itemId === 'ITEM-0145')?.quantity).toBe(1)
    expect(save.equipment.slots[WEAPON_TOOL_SLOT_ID]?.itemId).not.toBe('ITEM-0125')
  })

  it('blocks equipping an off-hand dagger while a dagger is already in the main hand', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      inventory: [],
      equipment: {
        ...save.equipment,
        slots: {
          ...save.equipment.slots,
          [WEAPON_TOOL_SLOT_ID]: { itemId: 'ITEM-0125', quantity: 1 },
        },
      },
    }
    save = addItemToInventory(save, 'ITEM-0225', 1) // Bronze Dagger
    const result = equipItemFromInventory(launch, save, 'ITEM-0225')
    expect(result.ok).toBe(false)
  })
})
