import type { EquippedStack, InventoryStack, PlayerSave } from './types'
import {
  RETIRED_FISHING_NET_ITEM_ID,
  STARTING_HUNTING_TOOL_ID,
  WEAPON_TOOL_SLOT_ID,
} from './types'

function hasItem(save: PlayerSave, itemId: string): boolean {
  if (save.inventory.some((stack) => stack.itemId === itemId && stack.quantity > 0)) {
    return true
  }
  return Object.values(save.equipment.slots).some(
    (stack) => stack?.itemId === itemId && stack.quantity > 0,
  )
}

/** Ensure the demo hunting Net is owned and equipped when the tool slot is free. */
export function ensureStartingHuntingTool(save: PlayerSave): PlayerSave {
  const slots: Record<string, EquippedStack | null> = { ...save.equipment.slots }
  let inventory = save.inventory.map((stack) => ({ ...stack }))
  const weapon = slots[WEAPON_TOOL_SLOT_ID]

  if (!hasItem({ ...save, inventory, equipment: { slots } }, STARTING_HUNTING_TOOL_ID)) {
    if (!weapon) {
      slots[WEAPON_TOOL_SLOT_ID] = { itemId: STARTING_HUNTING_TOOL_ID, quantity: 1 }
    } else {
      const existing = inventory.find((stack) => stack.itemId === STARTING_HUNTING_TOOL_ID)
      if (existing) existing.quantity += 1
      else inventory = [...inventory, { itemId: STARTING_HUNTING_TOOL_ID, quantity: 1 }]
    }
    return {
      ...save,
      inventory,
      equipment: { slots },
    }
  }

  // Already owned: equip it if the weapon/tool slot is empty.
  if (!weapon) {
    const invStack = inventory.find((stack) => stack.itemId === STARTING_HUNTING_TOOL_ID)
    if (invStack && invStack.quantity > 0) {
      inventory = inventory
        .map((stack) =>
          stack.itemId === STARTING_HUNTING_TOOL_ID
            ? { ...stack, quantity: stack.quantity - 1 }
            : stack,
        )
        .filter((stack) => stack.quantity > 0)
      slots[WEAPON_TOOL_SLOT_ID] = { itemId: STARTING_HUNTING_TOOL_ID, quantity: 1 }
      return {
        ...save,
        inventory,
        equipment: { slots },
      }
    }
  }

  return save
}

function remapRetiredNetId(itemId: string): string {
  return itemId === RETIRED_FISHING_NET_ITEM_ID ? STARTING_HUNTING_TOOL_ID : itemId
}

function stackMergeKey(stack: InventoryStack | EquippedStack): string {
  const enchantment = stack.enchantmentId ?? ''
  const favorite = stack.favorite === true ? '1' : '0'
  return `${stack.itemId}\0${enchantment}\0${favorite}`
}

function mergeRemappedStacks<T extends InventoryStack>(stacks: T[]): T[] {
  const merged: T[] = []
  const indexByKey = new Map<string, number>()
  for (const stack of stacks) {
    const next = { ...stack, itemId: remapRetiredNetId(stack.itemId) }
    const key = stackMergeKey(next)
    const existingIndex = indexByKey.get(key)
    if (existingIndex == null) {
      indexByKey.set(key, merged.length)
      merged.push(next)
      continue
    }
    const existing = merged[existingIndex]
    if (!existing) continue
    merged[existingIndex] = {
      ...existing,
      quantity: existing.quantity + next.quantity,
    }
  }
  return merged
}

const RETIRED_ITEM_IDS = new Set([
  'ITEM-0091', // Gem Setting
  'ITEM-0096', // Steel Spear Head
  'ITEM-0144', // Enchanted Sword
  'ITEM-0286', // Bone Shard
  'ITEM-0325', // Golden Spud Seed
  'ITEM-0346', // Hunting Trap
])

function isRetiredItemId(itemId: string | null | undefined): boolean {
  return typeof itemId === 'string' && RETIRED_ITEM_IDS.has(itemId)
}

function dropRetiredStacks<T extends InventoryStack>(stacks: T[]): T[] {
  return stacks.filter((stack) => !isRetiredItemId(stack.itemId))
}

function dropRetiredEquipped(stack: EquippedStack | null): EquippedStack | null {
  if (!stack || isRetiredItemId(stack.itemId)) return null
  return stack
}

/** Strip deleted leftover stacks so they cannot show as raw item IDs. */
export function removeRetiredItems(save: PlayerSave): PlayerSave {
  const slots: Record<string, EquippedStack | null> = {}
  for (const [slotId, stack] of Object.entries(save.equipment.slots)) {
    slots[slotId] = dropRetiredEquipped(stack)
  }
  const presets = (save.equipmentPresets ?? []).map((preset) => ({
    ...preset,
    slots: Object.fromEntries(
      Object.entries(preset.slots ?? {}).map(([slotId, stack]) => [
        slotId,
        dropRetiredEquipped(stack),
      ]),
    ),
  }))
  const locationTimers = (save.locationTimers ?? []).filter(
    (timer) => !isRetiredItemId(timer.inputItemId) && !isRetiredItemId(timer.outputItemId),
  )
  const lootTrackers = Object.fromEntries(
    Object.entries(save.lootTrackers ?? {}).map(([key, entry]) => [
      key,
      {
        ...entry,
        items: Object.fromEntries(
          Object.entries(entry.items ?? {}).filter(([itemId]) => !isRetiredItemId(itemId)),
        ),
      },
    ]),
  )
  return {
    ...save,
    inventory: dropRetiredStacks(save.inventory),
    bank: dropRetiredStacks(save.bank ?? []),
    equipment: { ...save.equipment, slots },
    equipmentPresets: presets,
    locationTimers,
    lootTrackers,
  }
}

/** Turn leftover Fishing Nets into the regular hunting Net. */
export function replaceFishingNetsWithNet(save: PlayerSave): PlayerSave {
  const slots: Record<string, EquippedStack | null> = {}
  for (const [slotId, stack] of Object.entries(save.equipment.slots)) {
    slots[slotId] = stack ? { ...stack, itemId: remapRetiredNetId(stack.itemId) } : null
  }
  return {
    ...save,
    inventory: mergeRemappedStacks(save.inventory),
    bank: mergeRemappedStacks(save.bank ?? []),
    equipment: { ...save.equipment, slots },
  }
}
