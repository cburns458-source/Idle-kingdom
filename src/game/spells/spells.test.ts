import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { playerDamageRange } from '../combat/stats'
import { prepareDatabase } from '../data/loadDatabase'
import { addItemToInventory } from '../activity/rewards'
import { equipItemFromInventory, unequipSlot } from '../equipment/loadout'
import { createNewSave } from '../save/saveStore'
import {
  activeSpellDamageRangeMultiplier,
  activeSpellItemDoubleChancePercent,
  firstEmptySpellSlot,
  SPELL_SLOT_IDS,
} from './spells'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'public/data/game-database.json'), 'utf8'),
)

describe('spell slots and Strength Spell', () => {
  it('includes Launch spell slots and the Strength Spell project', () => {
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

  it('applies Strength Spell while equipped in any slot (always on)', () => {
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

  it('stacks duplicate Strength Spells additively', () => {
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

  it('includes Abundance Spell project and stacks double-chance', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(launch.Items.some((item) => item['Item ID'] === 'ITEM-0297')).toBe(true)
    expect(launch.Projects.some((project) => project['Project ID'] === 'PRJ-0141')).toBe(true)
    const project = launch.Projects.find((row) => row['Project ID'] === 'PRJ-0141')!
    expect(project['Required Skill 1 Level']).toBe(40)
    expect(project['Input 1 Item ID']).toBe('ITEM-0099')
    expect(project['Input 2 Item ID']).toBe('ITEM-0026')

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
