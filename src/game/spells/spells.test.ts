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
  activeSpellSlotId,
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

  it('applies +10% damage range while Strength Spell occupies the active cycle slot', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    // Clear hunting net so unarmed range is used.
    save = unequipSlot(save, 'SLOT-0001')
    const base = playerDamageRange(launch, save, 0)

    save = addItemToInventory(save, 'ITEM-0295', 1)
    const equipped = equipItemFromInventory(launch, save, 'ITEM-0295')
    expect(equipped.ok).toBe(true)
    if (!equipped.ok) return
    save = equipped.save

    // Force cycle onto SLOT-0013 (index 0).
    const now = 0
    expect(activeSpellSlotId(launch, now)).toBe('SLOT-0013')
    expect(activeSpellDamageRangeMultiplier(launch, save, now)).toBeCloseTo(1.1)
    const buffed = playerDamageRange(launch, save, now)
    expect(buffed.min).toBe(Math.floor(base.min * 1.1))
    expect(buffed.max).toBe(Math.floor(base.max * 1.1))

    // Next hour: SLOT-0014 empty => no spell multiplier.
    const later = 3_600_000
    expect(activeSpellSlotId(launch, later)).toBe('SLOT-0014')
    expect(activeSpellDamageRangeMultiplier(launch, save, later)).toBe(1)
  })
})
