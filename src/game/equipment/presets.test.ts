import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { addItemToInventory } from '../activity/rewards'
import { prepareDatabase } from '../data/loadDatabase'
import { INVENTORY_SLOT_LIMIT } from '../inventory/capacity'
import { createNewSave } from '../save/saveStore'
import { migrateSave } from '../save/migrations'
import { SAVE_VERSION } from '../save/types'
import { equipItemFromInventory } from './loadout'
import {
  applyEquipmentPreset,
  renameEquipmentPreset,
  saveActiveEquipmentPreset,
  setEquipmentPresetIcon,
  setEquipmentPresetSlot,
  trackActiveEquipmentPreset,
} from './presets'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('equipment presets', () => {
  it('creates four default presets and migrates older saves', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    expect(save.equipmentPresets).toHaveLength(4)
    expect(save.equipmentPresets[0]?.name).toBe('Preset 1')
    expect(save.activeEquipmentPresetIndex).toBe(0)

    const legacy = structuredClone(save)
    legacy.saveVersion = 36
    delete (legacy as { equipmentPresets?: unknown }).equipmentPresets
    const migrated = migrateSave(legacy)
    expect(migrated.saveVersion).toBe(SAVE_VERSION)
    expect(migrated.equipmentPresets).toHaveLength(4)
  })

  it('auto-tracks preset 1 while active and saves snapshots for others', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = addItemToInventory(save, 'ITEM-0111', 1)
    const equipped = equipItemFromInventory(launch, save, 'ITEM-0111')
    expect(equipped.ok).toBe(true)
    if (!equipped.ok) return
    save = trackActiveEquipmentPreset(equipped.save)
    expect(save.equipmentPresets[0]?.slots['SLOT-0001']?.itemId).toBe('ITEM-0111')

    const toTwo = applyEquipmentPreset(launch, save, 1)
    expect(toTwo.ok).toBe(true)
    if (!toTwo.ok) return
    expect(toTwo.save.activeEquipmentPresetIndex).toBe(1)
    expect(toTwo.save.equipment.slots['SLOT-0001']).toBeNull()
    expect(toTwo.save.inventory.some((stack) => stack.itemId === 'ITEM-0111')).toBe(true)

    let onTwo = toTwo.save
    onTwo = addItemToInventory(onTwo, 'ITEM-0110', 1)
    const hatchet = equipItemFromInventory(launch, onTwo, 'ITEM-0110')
    expect(hatchet.ok).toBe(true)
    if (!hatchet.ok) return
    onTwo = saveActiveEquipmentPreset(hatchet.save)
    expect(onTwo.equipmentPresets[1]?.slots['SLOT-0001']?.itemId).toBe('ITEM-0110')

    const back = applyEquipmentPreset(launch, onTwo, 0)
    expect(back.ok).toBe(true)
    if (!back.ok) return
    expect(back.save.equipment.slots['SLOT-0001']?.itemId).toBe('ITEM-0111')
  })

  it('blocks preset swaps when the bag cannot hold unequipped gear', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      equipment: {
        slots: {
          ...save.equipment.slots,
          'SLOT-0001': { itemId: 'ITEM-0111', quantity: 1 },
        },
      },
      equipmentPresets: save.equipmentPresets.map((preset, index) =>
        index === 0
          ? {
              ...preset,
              slots: {
                ...preset.slots,
                'SLOT-0001': { itemId: 'ITEM-0111', quantity: 1 },
              },
            }
          : preset,
      ),
      activeEquipmentPresetIndex: 0,
      inventory: Array.from({ length: INVENTORY_SLOT_LIMIT }, (_, i) => ({
        itemId: `ITEM-PAD-${i}`,
        quantity: 1,
      })),
    }
    const blocked = applyEquipmentPreset(launch, save, 1)
    expect(blocked.ok).toBe(false)
    if (blocked.ok) return
    expect(blocked.reason).toMatch(/inventory space/i)
  })

  it('equips owned pieces and leaves missing slots empty without rewriting the snapshot', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = addItemToInventory(save, 'ITEM-0111', 1)
    const equipped = equipItemFromInventory(launch, save, 'ITEM-0111')
    expect(equipped.ok).toBe(true)
    if (!equipped.ok) return
    save = trackActiveEquipmentPreset(equipped.save)
    save = {
      ...save,
      equipmentPresets: save.equipmentPresets.map((preset, index) =>
        index === 1
          ? {
              ...preset,
              slots: {
                ...preset.slots,
                'SLOT-0001': { itemId: 'ITEM-0111', quantity: 1 },
                'SLOT-0003': { itemId: 'ITEM-0155', quantity: 1 },
              },
            }
          : preset,
      ),
    }

    const applied = applyEquipmentPreset(launch, save, 1)
    expect(applied.ok).toBe(true)
    if (!applied.ok) return
    expect(applied.warning).toBe('Some items were missing.')
    expect(applied.save.equipment.slots['SLOT-0001']?.itemId).toBe('ITEM-0111')
    expect(applied.save.equipment.slots['SLOT-0003']).toBeNull()
    expect(applied.save.equipmentPresets[1]?.slots['SLOT-0003']?.itemId).toBe('ITEM-0155')

    const withHelm = addItemToInventory(applied.save, 'ITEM-0155', 1)
    const toOne = applyEquipmentPreset(launch, withHelm, 0)
    expect(toOne.ok).toBe(true)
    if (!toOne.ok) return
    const again = applyEquipmentPreset(launch, toOne.save, 1)
    expect(again.ok).toBe(true)
    if (!again.ok) return
    expect(again.warning).toBeUndefined()
    expect(again.save.equipment.slots['SLOT-0003']?.itemId).toBe('ITEM-0155')
  })

  it('keeps an unowned stored piece on preset 1 and clears it when the piece is still in the bag', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      equipment: {
        slots: {
          ...save.equipment.slots,
          'SLOT-0001': { itemId: 'ITEM-0111', quantity: 1 },
        },
      },
      equipmentPresets: save.equipmentPresets.map((preset, index) =>
        index === 0
          ? {
              ...preset,
              slots: {
                ...preset.slots,
                'SLOT-0001': { itemId: 'ITEM-0111', quantity: 1 },
                'SLOT-0003': { itemId: 'ITEM-0155', quantity: 1 },
              },
            }
          : preset,
      ),
      activeEquipmentPresetIndex: 0,
    }
    const kept = trackActiveEquipmentPreset(save)
    expect(kept.equipmentPresets[0]?.slots['SLOT-0001']?.itemId).toBe('ITEM-0111')
    expect(kept.equipmentPresets[0]?.slots['SLOT-0003']?.itemId).toBe('ITEM-0155')

    const withHelm = addItemToInventory(save, 'ITEM-0155', 1)
    const cleared = trackActiveEquipmentPreset(withHelm)
    expect(cleared.equipmentPresets[0]?.slots['SLOT-0003']).toBeNull()
  })

  it('writes a snapshot slot without changing worn gear or the active preset', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = addItemToInventory(save, 'ITEM-0111', 1)
    const equipped = equipItemFromInventory(launch, save, 'ITEM-0111')
    expect(equipped.ok).toBe(true)
    if (!equipped.ok) return
    save = equipped.save
    const next = setEquipmentPresetSlot(launch, save, 1, 'SLOT-0001', {
      itemId: 'ITEM-0110',
      quantity: 1,
    })
    expect(next.activeEquipmentPresetIndex).toBe(0)
    expect(next.equipment.slots['SLOT-0001']?.itemId).toBe('ITEM-0111')
    expect(next.equipmentPresets[1]?.slots['SLOT-0001']?.itemId).toBe('ITEM-0110')
  })

  it('renames presets and sets icons', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = renameEquipmentPreset(save, 1, 'Mining Kit')
    save = setEquipmentPresetIcon(save, 1, {
      kind: 'skill',
      numeral: null,
      skillId: 'SKL-0002',
    })
    expect(save.equipmentPresets[1]?.name).toBe('Mining Kit')
    expect(save.equipmentPresets[1]?.icon).toEqual({
      kind: 'skill',
      numeral: null,
      skillId: 'SKL-0002',
    })
  })
})
