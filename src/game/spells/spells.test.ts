import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { playerDamageRange, playerDamageReduction } from '../combat/stats'
import { prepareDatabase } from '../data/loadDatabase'
import { addItemToInventory } from '../activity/rewards'
import { equipItemFromInventory, unequipSlot } from '../equipment/loadout'
import { createNewSave } from '../save/saveStore'
import { playerBuyPrice } from '../shops/shops'
import {
  activeSpellDamageRangeMultiplier,
  activeSpellDamageReductionPercent,
  activeSpellGatheringDurationMultiplier,
  activeSpellGoldDoubleChancePercent,
  activeSpellItemDoubleChancePercent,
  activeSpellLifestealPercent,
  activeSpellProductionDurationMultiplier,
  equippedSpellPowerMultiplier,
  firstEmptySpellSlot,
  SPELL_SLOT_IDS,
} from './spells'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('spell slots and Strength spell', () => {
  it('includes Launch spell slots and the Strength spell project', () => {
    const { launch } = prepareDatabase(rawDatabase)
    for (const slotId of SPELL_SLOT_IDS) {
      expect(launch.EquipmentSlots.some((slot) => slot['Slot ID'] === slotId)).toBe(true)
    }
    expect(launch.Items.some((item) => item['Item ID'] === 'ITEM-0295')).toBe(true)
    expect(launch.Projects.some((project) => project['Project ID'] === 'PRJ-0139')).toBe(true)
    expect(launch.Enchantments.some((row) => row['Enchantment ID'] === 'ENCH-0005')).toBe(true)
  })

  it('equips the same spell into multiple empty spell slots', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = addItemToInventory(save, 'ITEM-0295', 3)

    const first = equipItemFromInventory(launch, save, 'ITEM-0295')
    expect(first.ok).toBe(true)
    if (!first.ok) return
    save = first.save
    expect(save.equipment.slots['SLOT-0013']?.itemId).toBe('ITEM-0295')

    const second = equipItemFromInventory(launch, save, 'ITEM-0295')
    expect(second.ok).toBe(true)
    if (!second.ok) return
    save = second.save
    expect(save.equipment.slots['SLOT-0014']?.itemId).toBe('ITEM-0295')
    expect(firstEmptySpellSlot(save)).toBe('SLOT-0015')
  })

  it('applies Strength spell while equipped in any slot (always on)', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    const clearedNet = unequipSlot(save, 'SLOT-0001')
    expect(clearedNet.ok).toBe(true)
    if (!clearedNet.ok) return
    save = clearedNet.save
    const base = playerDamageRange(launch, save)

    save = addItemToInventory(save, 'ITEM-0295', 1)
    const equipped = equipItemFromInventory(launch, save, 'ITEM-0295')
    expect(equipped.ok).toBe(true)
    if (!equipped.ok) return
    save = equipped.save

    expect(save.equipment.slots['SLOT-0013']?.itemId).toBe('ITEM-0295')
    expect(activeSpellDamageRangeMultiplier(launch, save)).toBeCloseTo(1.1)
    const buffed = playerDamageRange(launch, save)
    expect(buffed.min).toBe(Math.floor(base.min * 1.1))
    expect(buffed.max).toBe(Math.floor(base.max * 1.1))
  })

  it('stacks duplicate Strength spells additively', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = addItemToInventory(save, 'ITEM-0295', 2)

    const first = equipItemFromInventory(launch, save, 'ITEM-0295')
    expect(first.ok).toBe(true)
    if (!first.ok) return
    save = first.save
    const second = equipItemFromInventory(launch, save, 'ITEM-0295')
    expect(second.ok).toBe(true)
    if (!second.ok) return
    save = second.save

    expect(activeSpellDamageRangeMultiplier(launch, save)).toBeCloseTo(1.2)
  })

  it('includes Abundance spell project and stacks double-chance', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(launch.Items.some((item) => item['Item ID'] === 'ITEM-0297')).toBe(true)
    expect(launch.Projects.some((project) => project['Project ID'] === 'PRJ-0141')).toBe(true)
    const project = launch.Projects.find((row) => row['Project ID'] === 'PRJ-0141')!
    expect(project['Required Skill 1 Level']).toBe(40)
    expect(project['Input 1 Item ID']).toBe('ITEM-0099')
    expect(project['Input 2 Item ID']).toBe('ITEM-0026')
    expect(project['Input 3 Item ID']).toBe('ITEM-0413')
    expect(project['Input 3 Quantity']).toBe(10)
    expect(project['Input 4 Item ID']).toBe('ITEM-0011')

    let save = createNewSave(launch)
    save = addItemToInventory(save, 'ITEM-0297', 2)
    const first = equipItemFromInventory(launch, save, 'ITEM-0297')
    expect(first.ok).toBe(true)
    if (!first.ok) return
    save = first.save
    expect(activeSpellItemDoubleChancePercent(launch, save)).toBe(10)

    const second = equipItemFromInventory(launch, save, 'ITEM-0297')
    expect(second.ok).toBe(true)
    if (!second.ok) return
    save = second.save
    expect(activeSpellItemDoubleChancePercent(launch, save)).toBe(20)
  })
})

function equipItem(
  db: ReturnType<typeof prepareDatabase>['launch'],
  save: ReturnType<typeof createNewSave>,
  itemId: string,
  quantity = 1,
) {
  let next = addItemToInventory(save, itemId, quantity)
  const equipped = equipItemFromInventory(db, next, itemId)
  expect(equipped.ok).toBe(true)
  if (!equipped.ok) throw new Error(`failed to equip ${itemId}`)
  return equipped.save
}

describe("Wizard's tome spell power", () => {
  it('sells the Tome at the Wizard Shop for 314 and carries no HP or DR', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const item = launch.Items.find((row) => row['Item ID'] === 'ITEM-0149')!
    const equipment = launch.Equipment.find((row) => row['Equipment ID'] === 'EQP-0067')!
    const shop = launch.Shops.find((row) => row['Shop ID'] === 'SHP-0003')!
    expect(item['Base Sell Value']).toBe(157)
    expect(item.Description).toBe('Equipped spells are 20% stronger.')
    expect(equipment['HP Bonus']).toBeNull()
    expect(equipment['Damage Reduction']).toBeNull()
    expect(equipment['Capabilities / Effects']).toContain('spell_power_pct=20')
    expect(playerBuyPrice(launch, shop, 'ITEM-0149')).toBe(314)
  })

  it('does nothing when no spells are equipped', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    const baseDamage = activeSpellDamageRangeMultiplier(launch, save)
    const baseDr = activeSpellDamageReductionPercent(launch, save)
    const baseItems = activeSpellItemDoubleChancePercent(launch, save)
    const baseGold = activeSpellGoldDoubleChancePercent(launch, save)
    const baseLifesteal = activeSpellLifestealPercent(launch, save)
    const baseHaste = activeSpellProductionDurationMultiplier(launch, save)
    const basePathfinder = activeSpellGatheringDurationMultiplier(launch, save)
    save = equipItem(launch, save, 'ITEM-0149')
    expect(save.equipment.slots['SLOT-0002']?.itemId).toBe('ITEM-0149')
    expect(equippedSpellPowerMultiplier(launch, save)).toBeCloseTo(1.2)
    expect(activeSpellDamageRangeMultiplier(launch, save)).toBe(baseDamage)
    expect(activeSpellDamageReductionPercent(launch, save)).toBe(baseDr)
    expect(activeSpellItemDoubleChancePercent(launch, save)).toBe(baseItems)
    expect(activeSpellGoldDoubleChancePercent(launch, save)).toBe(baseGold)
    expect(activeSpellLifestealPercent(launch, save)).toBe(baseLifesteal)
    expect(activeSpellProductionDurationMultiplier(launch, save)).toBe(baseHaste)
    expect(activeSpellGatheringDurationMultiplier(launch, save)).toBe(basePathfinder)
  })

  it('raises Strength spell +10% damage to +12%', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    const cleared = unequipSlot(save, 'SLOT-0001')
    expect(cleared.ok).toBe(true)
    if (!cleared.ok) return
    save = cleared.save
    const base = playerDamageRange(launch, save)
    save = equipItem(launch, save, 'ITEM-0295')
    expect(activeSpellDamageRangeMultiplier(launch, save)).toBeCloseTo(1.1)
    const withoutTome = playerDamageRange(launch, save)
    expect(withoutTome.min).toBe(Math.floor(base.min * 1.1))
    expect(withoutTome.max).toBe(Math.floor(base.max * 1.1))

    save = equipItem(launch, save, 'ITEM-0149')
    expect(activeSpellDamageRangeMultiplier(launch, save)).toBeCloseTo(1.12)
    const withTome = playerDamageRange(launch, save)
    expect(withTome.min).toBe(Math.floor(base.min * 1.12))
    expect(withTome.max).toBe(Math.floor(base.max * 1.12))
  })

  it('raises Iron Ward damage reduction by 20%', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    const gearDr = playerDamageReduction(launch, save)
    save = equipItem(launch, save, 'ITEM-0395')
    expect(activeSpellDamageReductionPercent(launch, save)).toBe(5)
    expect(playerDamageReduction(launch, save)).toBe(gearDr + 5)

    save = equipItem(launch, save, 'ITEM-0149')
    expect(activeSpellDamageReductionPercent(launch, save)).toBe(6)
    expect(playerDamageReduction(launch, save)).toBe(gearDr + 6)
  })

  it('caps Tome-boosted double chance at 100%', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const patched = {
      ...launch,
      Equipment: launch.Equipment.map((row) =>
        row['Item ID'] === 'ITEM-0297'
          ? { ...row, 'Capabilities / Effects': 'spell; item_double_chance_percent:90' }
          : row,
      ),
    }
    let save = createNewSave(patched)
    save = equipItem(patched, save, 'ITEM-0297')
    expect(activeSpellItemDoubleChancePercent(patched, save)).toBe(90)
    save = equipItem(patched, save, 'ITEM-0149')
    expect(activeSpellItemDoubleChancePercent(patched, save)).toBe(100)

    const goldPatched = {
      ...launch,
      Equipment: launch.Equipment.map((row) =>
        row['Item ID'] === 'ITEM-0394'
          ? { ...row, 'Capabilities / Effects': 'spell; gold_double_chance_percent:90' }
          : row,
      ),
    }
    save = createNewSave(goldPatched)
    save = equipItem(goldPatched, save, 'ITEM-0394')
    expect(activeSpellGoldDoubleChancePercent(goldPatched, save)).toBe(90)
    save = equipItem(goldPatched, save, 'ITEM-0149')
    expect(activeSpellGoldDoubleChancePercent(goldPatched, save)).toBe(100)
  })

  it('raises Lifesteal 5% to 6% and still caps at 100%', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = equipItem(launch, save, 'ITEM-0396')
    expect(activeSpellLifestealPercent(launch, save)).toBe(5)
    save = equipItem(launch, save, 'ITEM-0149')
    expect(activeSpellLifestealPercent(launch, save)).toBe(6)

    const patched = {
      ...launch,
      Equipment: launch.Equipment.map((row) =>
        row['Item ID'] === 'ITEM-0396'
          ? { ...row, 'Capabilities / Effects': 'spell; lifesteal_percent:90' }
          : row,
      ),
    }
    save = createNewSave(patched)
    save = equipItem(patched, save, 'ITEM-0396')
    expect(activeSpellLifestealPercent(patched, save)).toBe(90)
    save = equipItem(patched, save, 'ITEM-0149')
    expect(activeSpellLifestealPercent(patched, save)).toBe(100)
  })

  it('raises Haste 10% duration cut to 12% and still floors at 0.01', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = equipItem(launch, save, 'ITEM-0398')
    expect(activeSpellProductionDurationMultiplier(launch, save)).toBeCloseTo(0.9)
    save = equipItem(launch, save, 'ITEM-0149')
    expect(activeSpellProductionDurationMultiplier(launch, save)).toBeCloseTo(0.88)

    const patched = {
      ...launch,
      Equipment: launch.Equipment.map((row) =>
        row['Item ID'] === 'ITEM-0398'
          ? { ...row, 'Capabilities / Effects': 'spell; production_duration_reduction_percent:90' }
          : row,
      ),
    }
    save = createNewSave(patched)
    save = equipItem(patched, save, 'ITEM-0398')
    expect(activeSpellProductionDurationMultiplier(patched, save)).toBeCloseTo(0.1)
    save = equipItem(patched, save, 'ITEM-0149')
    expect(activeSpellProductionDurationMultiplier(patched, save)).toBe(0.01)
  })

  it('raises Pathfinder 10% duration cut to 12% and still floors at 0.01', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = equipItem(launch, save, 'ITEM-0399')
    expect(activeSpellGatheringDurationMultiplier(launch, save)).toBeCloseTo(0.9)
    save = equipItem(launch, save, 'ITEM-0149')
    expect(activeSpellGatheringDurationMultiplier(launch, save)).toBeCloseTo(0.88)

    const patched = {
      ...launch,
      Equipment: launch.Equipment.map((row) =>
        row['Item ID'] === 'ITEM-0399'
          ? { ...row, 'Capabilities / Effects': 'spell; gathering_duration_reduction_percent:90' }
          : row,
      ),
    }
    save = createNewSave(patched)
    save = equipItem(patched, save, 'ITEM-0399')
    expect(activeSpellGatheringDurationMultiplier(patched, save)).toBeCloseTo(0.1)
    save = equipItem(patched, save, 'ITEM-0149')
    expect(activeSpellGatheringDurationMultiplier(patched, save)).toBe(0.01)
  })
})
