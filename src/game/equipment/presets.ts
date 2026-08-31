import type { GameDatabase } from '../data/types'
import { addItemToInventory } from '../activity/rewards'
import { canFitItemQuantity } from '../inventory/capacity'
import type {
  EquipmentPreset,
  EquipmentPresetIcon,
  EquippedStack,
  PlayerSave,
} from '../save/types'
import type { EquipResult } from './loadout'

export const EQUIPMENT_PRESET_COUNT = 4
export const EQUIPMENT_PRESET_NAME_MAX = 24

const BAG_FULL_REASON = 'Not enough inventory space to switch presets.'
const MISSING_REASON = 'Missing items needed for that preset.'

export function defaultEquipmentPresetIcon(index: number): EquipmentPresetIcon {
  return { kind: 'roman', numeral: index + 1, skillId: null }
}

export function emptyPresetSlots(
  slotIds: Iterable<string>,
): Record<string, EquippedStack | null> {
  const slots: Record<string, EquippedStack | null> = {}
  for (const slotId of slotIds) slots[slotId] = null
  return slots
}

export function cloneEquippedStack(stack: EquippedStack | null): EquippedStack | null {
  if (!stack) return null
  const next: EquippedStack = {
    itemId: stack.itemId,
    quantity: stack.quantity,
  }
  if (stack.enchantmentId) next.enchantmentId = stack.enchantmentId
  if (stack.favorite === true) next.favorite = true
  return next
}

export function clonePresetSlots(
  slots: Record<string, EquippedStack | null>,
): Record<string, EquippedStack | null> {
  const out: Record<string, EquippedStack | null> = {}
  for (const [slotId, stack] of Object.entries(slots)) {
    out[slotId] = cloneEquippedStack(stack)
  }
  return out
}

export function createDefaultEquipmentPresets(
  slotIds: Iterable<string>,
): EquipmentPreset[] {
  const empty = emptyPresetSlots(slotIds)
  return Array.from({ length: EQUIPMENT_PRESET_COUNT }, (_, index) => ({
    name: `Preset ${index + 1}`,
    icon: defaultEquipmentPresetIcon(index),
    slots: clonePresetSlots(empty),
  }))
}

export function normalizeEquipmentPresets(
  save: Pick<PlayerSave, 'equipment' | 'equipmentPresets' | 'activeEquipmentPresetIndex'>,
): Pick<PlayerSave, 'equipmentPresets' | 'activeEquipmentPresetIndex'> {
  const slotIds = Object.keys(save.equipment.slots)
  const defaults = createDefaultEquipmentPresets(slotIds)
  const raw = Array.isArray(save.equipmentPresets) ? save.equipmentPresets : []
  const presets = defaults.map((fallback, index) => {
    const row = raw[index]
    if (!row || typeof row !== 'object') return fallback
    const name =
      typeof row.name === 'string' && row.name.trim()
        ? row.name.trim().slice(0, EQUIPMENT_PRESET_NAME_MAX)
        : fallback.name
    const icon = normalizePresetIcon(row.icon, index)
    const slots = { ...fallback.slots }
    if (row.slots && typeof row.slots === 'object') {
      for (const slotId of slotIds) {
        slots[slotId] = cloneEquippedStack(
          (row.slots as Record<string, EquippedStack | null>)[slotId] ?? null,
        )
      }
    }
    return { name, icon, slots }
  })
  const active = Math.max(
    0,
    Math.min(
      EQUIPMENT_PRESET_COUNT - 1,
      Math.floor(Number(save.activeEquipmentPresetIndex) || 0),
    ),
  )
  return { equipmentPresets: presets, activeEquipmentPresetIndex: active }
}

function normalizePresetIcon(
  icon: EquipmentPresetIcon | null | undefined,
  index: number,
): EquipmentPresetIcon {
  if (!icon || typeof icon !== 'object') return defaultEquipmentPresetIcon(index)
  const kind = typeof icon.kind === 'string' ? icon.kind : 'roman'
  if (kind === 'coin') return { kind: 'coin', numeral: null, skillId: null }
  if (kind === 'skill' && typeof icon.skillId === 'string' && icon.skillId) {
    return { kind: 'skill', numeral: null, skillId: icon.skillId }
  }
  const numeral = Math.max(1, Math.min(4, Math.floor(Number(icon.numeral) || index + 1)))
  return { kind: 'roman', numeral, skillId: null }
}

/** While preset 1 is active, keep its snapshot identical to the live loadout. */
export function trackActiveEquipmentPreset(save: PlayerSave): PlayerSave {
  const { equipmentPresets, activeEquipmentPresetIndex } = normalizeEquipmentPresets(save)
  if (activeEquipmentPresetIndex !== 0) {
    return { ...save, equipmentPresets, activeEquipmentPresetIndex }
  }
  const next = equipmentPresets.map((preset, index) =>
    index === 0
      ? { ...preset, slots: clonePresetSlots(save.equipment.slots) }
      : preset,
  )
  return { ...save, equipmentPresets: next, activeEquipmentPresetIndex }
}

export function saveActiveEquipmentPreset(save: PlayerSave): PlayerSave {
  const { equipmentPresets, activeEquipmentPresetIndex } = normalizeEquipmentPresets(save)
  const next = equipmentPresets.map((preset, index) =>
    index === activeEquipmentPresetIndex
      ? { ...preset, slots: clonePresetSlots(save.equipment.slots) }
      : preset,
  )
  return { ...save, equipmentPresets: next, activeEquipmentPresetIndex }
}

export function renameEquipmentPreset(
  save: PlayerSave,
  index: number,
  name: string,
): PlayerSave {
  const { equipmentPresets, activeEquipmentPresetIndex } = normalizeEquipmentPresets(save)
  if (index < 0 || index >= EQUIPMENT_PRESET_COUNT) return save
  const trimmed = name.trim().slice(0, EQUIPMENT_PRESET_NAME_MAX)
  if (!trimmed) return save
  const next = equipmentPresets.map((preset, i) =>
    i === index ? { ...preset, name: trimmed } : preset,
  )
  return { ...save, equipmentPresets: next, activeEquipmentPresetIndex }
}

export function setEquipmentPresetIcon(
  save: PlayerSave,
  index: number,
  icon: EquipmentPresetIcon,
): PlayerSave {
  const { equipmentPresets, activeEquipmentPresetIndex } = normalizeEquipmentPresets(save)
  if (index < 0 || index >= EQUIPMENT_PRESET_COUNT) return save
  const next = equipmentPresets.map((preset, i) =>
    i === index ? { ...preset, icon: normalizePresetIcon(icon, index) } : preset,
  )
  return { ...save, equipmentPresets: next, activeEquipmentPresetIndex }
}

type PoolEntry = {
  itemId: string
  quantity: number
  enchantmentId: string | null
  favorite: boolean
}

function stackKey(itemId: string, enchantmentId: string | null, favorite: boolean): string {
  return `${itemId}\0${enchantmentId ?? ''}\0${favorite ? '1' : '0'}`
}

function toPoolEntry(stack: EquippedStack): PoolEntry {
  return {
    itemId: stack.itemId,
    quantity: stack.quantity,
    enchantmentId: stack.enchantmentId ?? null,
    favorite: stack.favorite === true,
  }
}

function takeFromPool(pool: Map<string, PoolEntry>, need: EquippedStack): boolean {
  const key = stackKey(need.itemId, need.enchantmentId ?? null, need.favorite === true)
  const entry = pool.get(key)
  if (!entry || entry.quantity < need.quantity) return false
  entry.quantity -= need.quantity
  if (entry.quantity <= 0) pool.delete(key)
  return true
}

/**
 * Instant in-place swap to a stored preset. Blocks when the bag cannot hold
 * everything that would come off, or when preset pieces are missing.
 */
export function applyEquipmentPreset(
  _db: GameDatabase,
  save: PlayerSave,
  index: number,
): EquipResult {
  const normalized = normalizeEquipmentPresets(save)
  if (index < 0 || index >= EQUIPMENT_PRESET_COUNT) {
    return { ok: false, reason: 'That preset does not exist.' }
  }
  let working: PlayerSave = { ...save, ...normalized }
  if (working.activeEquipmentPresetIndex === 0) {
    working = trackActiveEquipmentPreset(working)
  }
  if (index === working.activeEquipmentPresetIndex) {
    return { ok: true, save: working }
  }

  const target = clonePresetSlots(working.equipmentPresets[index]!.slots)
  const slotIds = Object.keys(working.equipment.slots)

  const pool = new Map<string, PoolEntry>()
  const addToPool = (stack: EquippedStack) => {
    const key = stackKey(stack.itemId, stack.enchantmentId ?? null, stack.favorite === true)
    const existing = pool.get(key)
    if (existing) existing.quantity += stack.quantity
    else pool.set(key, toPoolEntry(stack))
  }

  for (const slotId of slotIds) {
    const equipped = working.equipment.slots[slotId]
    if (equipped && equipped.quantity > 0) addToPool(equipped)
  }
  for (const stack of working.inventory) {
    if (stack.quantity > 0) addToPool(stack as unknown as EquippedStack)
  }

  for (const slotId of slotIds) {
    const want = target[slotId]
    if (!want || want.quantity <= 0) continue
    if (!takeFromPool(pool, want)) {
      return { ok: false, reason: MISSING_REASON }
    }
  }

  // Remaining pool must fit in an empty-equipment bag (slots cleared).
  let bagProbe: PlayerSave = {
    ...working,
    equipment: {
      slots: Object.fromEntries(slotIds.map((id) => [id, null])),
    },
    inventory: [],
  }
  for (const entry of pool.values()) {
    if (
      !canFitItemQuantity(
        bagProbe,
        entry.itemId,
        entry.quantity,
        entry.enchantmentId,
        entry.favorite,
      )
    ) {
      return { ok: false, reason: BAG_FULL_REASON }
    }
    bagProbe = addItemToInventory(
      bagProbe,
      entry.itemId,
      entry.quantity,
      entry.enchantmentId,
      entry.favorite,
    )
  }

  return {
    ok: true,
    save: {
      ...working,
      equipment: { slots: target },
      inventory: bagProbe.inventory,
      activeEquipmentPresetIndex: index,
      equipmentPresets:
        index === 0
          ? working.equipmentPresets.map((preset, i) =>
              i === 0 ? { ...preset, slots: clonePresetSlots(target) } : preset,
            )
          : working.equipmentPresets,
    },
  }
}
