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
  editSelectedEquipmentPresetSlot,
  presetMatchesLoadout,
  renameEquipmentPreset,
  saveActiveEquipmentPreset,
  setEquipmentPresetIcon,
  setEquipmentPresetSlot,
  shouldHighlightEquipmentPreset,
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

  it('save snapshots the worn loadout; switching does not rewrite other presets', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = addItemToInventory(save, 'ITEM-0111', 1)
    const equipped = equipItemFromInventory(launch, save, 'ITEM-0111')
    expect(equipped.ok).toBe(true)
    if (!equipped.ok) return
    save = saveActiveEquipmentPreset(equipped.save)
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
    expect(onTwo.equipmentPresets[0]?.slots['SLOT-0001']?.itemId).toBe('ITEM-0111')

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
    save = saveActiveEquipmentPreset(equipped.save)
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

  it('does not copy worn gear onto a preset when tracking', () => {
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
    }
    const tracked = trackActiveEquipmentPreset(save)
    expect(tracked.equipmentPresets[0]?.slots['SLOT-0001']).toBeNull()
    expect(presetMatchesLoadout(tracked, 0)).toBe(false)
    expect(shouldHighlightEquipmentPreset(tracked, 0)).toBe(false)
  })

  it('matches loadouts by item identity and ignores food quantity', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      equipment: {
        slots: {
          ...save.equipment.slots,
          'SLOT-0001': { itemId: 'ITEM-0111', quantity: 1 },
          'SLOT-0011': { itemId: 'ITEM-0058', quantity: 2 },
        },
      },
      equipmentPresets: save.equipmentPresets.map((preset, index) =>
        index === 1
          ? {
              ...preset,
              slots: {
                ...preset.slots,
                'SLOT-0001': { itemId: 'ITEM-0111', quantity: 1 },
                'SLOT-0011': { itemId: 'ITEM-0058', quantity: 5 },
              },
            }
          : preset,
      ),
    }
    expect(presetMatchesLoadout(save, 1)).toBe(true)
    expect(shouldHighlightEquipmentPreset(save, 1)).toBe(false)
    save = { ...save, activeEquipmentPresetIndex: 1 }
    expect(shouldHighlightEquipmentPreset(save, 1)).toBe(true)
    expect(shouldHighlightEquipmentPreset(save, 0)).toBe(false)

    save = {
      ...save,
      equipment: {
        slots: {
          ...save.equipment.slots,
          'SLOT-0011': { itemId: 'ITEM-0059', quantity: 2 },
        },
      },
    }
    expect(presetMatchesLoadout(save, 1)).toBe(false)
  })

  it('matching clones do not highlight together', () => {
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
      activeEquipmentPresetIndex: 0,
      equipmentPresets: save.equipmentPresets.map((preset, index) =>
        index === 0 || index === 1
          ? {
              ...preset,
              slots: {
                ...preset.slots,
                'SLOT-0001': { itemId: 'ITEM-0111', quantity: 1 },
              },
            }
          : preset,
      ),
    }
    expect(presetMatchesLoadout(save, 0)).toBe(true)
    expect(presetMatchesLoadout(save, 1)).toBe(true)
    expect(shouldHighlightEquipmentPreset(save, 0)).toBe(true)
    expect(shouldHighlightEquipmentPreset(save, 1)).toBe(false)
  })

  it('editing a selected preset wears the new snapshot', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = addItemToInventory(save, 'ITEM-0111', 1)
    save = addItemToInventory(save, 'ITEM-0110', 1)
    const equipped = equipItemFromInventory(launch, save, 'ITEM-0111')
    expect(equipped.ok).toBe(true)
    if (!equipped.ok) return
    save = saveActiveEquipmentPreset(equipped.save)
    const next = editSelectedEquipmentPresetSlot(launch, save, 0, 'SLOT-0001', {
      itemId: 'ITEM-0110',
      quantity: 1,
    })
    expect(next.equipmentPresets[0]?.slots['SLOT-0001']?.itemId).toBe('ITEM-0110')
    expect(next.equipment.slots['SLOT-0001']?.itemId).toBe('ITEM-0110')
    expect(next.inventory.some((stack) => stack.itemId === 'ITEM-0111')).toBe(true)
  })

  it('applying the active preset still restores it after the loadout diverged', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = addItemToInventory(save, 'ITEM-0111', 1)
    save = addItemToInventory(save, 'ITEM-0110', 1)
    const equipped = equipItemFromInventory(launch, save, 'ITEM-0111')
    expect(equipped.ok).toBe(true)
    if (!equipped.ok) return
    save = saveActiveEquipmentPreset(equipped.save)
    const hatchet = equipItemFromInventory(launch, save, 'ITEM-0110')
    expect(hatchet.ok).toBe(true)
    if (!hatchet.ok) return
    save = hatchet.save
    expect(save.activeEquipmentPresetIndex).toBe(0)
    expect(save.equipment.slots['SLOT-0001']?.itemId).toBe('ITEM-0110')
    const restored = applyEquipmentPreset(launch, save, 0)
    expect(restored.ok).toBe(true)
    if (!restored.ok) return
    expect(restored.save.equipment.slots['SLOT-0001']?.itemId).toBe('ITEM-0111')
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
