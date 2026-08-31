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
import { productionCraftDurationMs } from '../production/engine'
import { INVENTORY_SLOT_LIMIT } from '../inventory/capacity'
import {
  equipInventoryIndex,
  equipItemFromInventory,
  equipStackToSlot,
  FOOD_SLOT_ID,
  isTwoHandedItem,
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

  it('applies action time reduction only to the tool\'s own skill', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = addItemToInventory(save, 'ITEM-0111', 1) // Copper Pickaxe, Mining ATR 3
    const equipped = equipItemFromInventory(launch, save, 'ITEM-0111')
    expect(equipped.ok).toBe(true)
    if (!equipped.ok) return

    const digClay = launch.Actions.find((action) => action['Action ID'] === 'ACN-0019')!
    const cutCedar = launch.Actions.find((action) => action['Action ID'] === 'ACN-0046')!
    const clayBase = Number(digClay['Base Duration Seconds'] ?? 0)
    const clayMult = 1 < Number(digClay['Proficiency Level'] ?? 1) ? 2 : 1
    const cedarBase = Number(cutCedar['Base Duration Seconds'] ?? 0)
    const cedarMult = 1 < Number(cutCedar['Proficiency Level'] ?? 1) ? 2 : 1
    expect(gatheringDurationMs(launch, equipped.save, digClay)).toBe(
      Math.round(clayBase * clayMult * 0.97 * 1000),
    )
    expect(gatheringDurationMs(launch, equipped.save, cutCedar)).toBe(
      Math.round(cedarBase * cedarMult * 1000),
    )
  })

  it('credits oven mitts action time to cooking and metallurgy production', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = addItemToInventory(save, 'ITEM-0316', 1)
    const equipped = equipItemFromInventory(launch, save, 'ITEM-0316')
    expect(equipped.ok).toBe(true)
    if (!equipped.ok) return

    const beef = launch.Recipes.find((recipe) => recipe['Recipe ID'] === 'RCP-0009')!
    const copper = launch.Recipes.find((recipe) => recipe['Recipe ID'] === 'RCP-0014')!
    expect(productionCraftDurationMs(launch, equipped.save, beef, null)).toBe(10_000 * 0.95)
    expect(productionCraftDurationMs(launch, equipped.save, copper, null)).toBe(15_000 * 0.95)
    expect(productionCraftDurationMs(launch, save, beef, null)).toBe(10_000)
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
    expect(migrated.cosmetics.unlocked).toEqual(['COS-0001', 'COS-0003'])
    expect(migrated.cosmetics.equipped['CSLOT-0001']).toBe('COS-0001')
    expect(migrated.cosmetics.equipped['CSLOT-0002']).toBeNull()
    expect(migrated.cosmetics.equipped['CSLOT-0003']).toBe('COS-0003')
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

  it('treats bows, battleaxes, warhammers, and battle staves as two-handed', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(isTwoHandedItem(launch, 'ITEM-0135')).toBe(true) // Regular Bow
    expect(isTwoHandedItem(launch, 'ITEM-0142')).toBe(true) // Steel Battleaxe
    expect(isTwoHandedItem(launch, 'ITEM-0143')).toBe(true) // Warhammer
    expect(isTwoHandedItem(launch, 'ITEM-0123')).toBe(true) // Dwarven Warhammer
    expect(isTwoHandedItem(launch, 'ITEM-0285')).toBe(true) // Ancient Bow
    expect(isTwoHandedItem(launch, 'ITEM-0304')).toBe(true)
    expect(isTwoHandedItem(launch, 'ITEM-0305')).toBe(true)
    expect(isTwoHandedItem(launch, 'ITEM-0306')).toBe(true)
    expect(isTwoHandedItem(launch, 'ITEM-0122')).toBe(false) // Goblin Staff
    expect(isTwoHandedItem(launch, 'ITEM-0307')).toBe(false) // Mage's Wand
    expect(isTwoHandedItem(launch, 'ITEM-0124')).toBe(false) // Wooden Sword
  })

  it('unequips the off-hand when a two-handed weapon is equipped', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      inventory: [],
      skills: save.skills.map((skill) =>
        skill.skillId === 'SKL-0001' || skill.skillId === 'SKL-0005'
          ? { ...skill, level: 10 }
          : skill,
      ),
    }
    save = addItemToInventory(save, 'ITEM-0145', 1) // Wooden Shield
    save = addItemToInventory(save, 'ITEM-0135', 1) // Regular Bow
    const shield = equipItemFromInventory(launch, save, 'ITEM-0145')
    expect(shield.ok).toBe(true)
    if (!shield.ok) return
    const bow = equipItemFromInventory(launch, shield.save, 'ITEM-0135')
    expect(bow.ok).toBe(true)
    if (!bow.ok) return
    expect(bow.save.equipment.slots[WEAPON_TOOL_SLOT_ID]?.itemId).toBe('ITEM-0135')
    expect(bow.save.equipment.slots[OFFHAND_SLOT_ID]).toBeNull()
    expect(bow.save.inventory.find((stack) => stack.itemId === 'ITEM-0145')?.quantity).toBe(1)
  })

  it('unequips a two-hander when an off-hand item is equipped', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      inventory: [],
      skills: save.skills.map((skill) =>
        skill.skillId === 'SKL-0001' || skill.skillId === 'SKL-0005'
          ? { ...skill, level: 10 }
          : skill,
      ),
    }
    save = addItemToInventory(save, 'ITEM-0135', 1)
    save = addItemToInventory(save, 'ITEM-0145', 1)
    const bow = equipItemFromInventory(launch, save, 'ITEM-0135')
    expect(bow.ok).toBe(true)
    if (!bow.ok) return
    const shield = equipItemFromInventory(launch, bow.save, 'ITEM-0145')
    expect(shield.ok).toBe(true)
    if (!shield.ok) return
    expect(shield.save.equipment.slots[OFFHAND_SLOT_ID]?.itemId).toBe('ITEM-0145')
    expect(shield.save.equipment.slots[WEAPON_TOOL_SLOT_ID]).toBeNull()
    expect(shield.save.inventory.find((stack) => stack.itemId === 'ITEM-0135')?.quantity).toBe(1)
  })

  it('blocks a two-hander when the bag cannot hold the off-hand item', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      inventory: [],
      skills: save.skills.map((skill) =>
        skill.skillId === 'SKL-0001' || skill.skillId === 'SKL-0005'
          ? { ...skill, level: 10 }
          : skill,
      ),
    }
    save = equipStackToSlot(save, WEAPON_TOOL_SLOT_ID, 'ITEM-0124', 1)
    save = equipStackToSlot(save, OFFHAND_SLOT_ID, 'ITEM-0145', 1)
    const filler = launch.Items.filter(
      (item) =>
        item['Item ID'] !== 'ITEM-0135' &&
        item['Item ID'] !== 'ITEM-0145' &&
        item['Item ID'] !== 'ITEM-0124',
    ).slice(0, INVENTORY_SLOT_LIMIT - 1)
    save = {
      ...save,
      inventory: [
        ...filler.map((item) => ({ itemId: item['Item ID'], quantity: 1 })),
        { itemId: 'ITEM-0135', quantity: 1 },
      ],
    }
    const result = equipItemFromInventory(launch, save, 'ITEM-0135')
    expect(result.ok).toBe(false)
    if (result.ok) return
    expect(result.reason).toMatch(/inventory space/i)
    expect(save.equipment.slots[OFFHAND_SLOT_ID]?.itemId).toBe('ITEM-0145')
  })
})
