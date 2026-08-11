import {
  canFitItemQuantity,
  INVENTORY_SLOT_LIMIT,
  INVENTORY_STACK_MAX,
  maxAddableQuantity,
} from '../inventory/capacity'
import { sortInventoryFavoritesFirst } from '../inventory/favorites'
import { isGoldCurrencyItem } from '../inventory/gold'
import {
  applyRelativeDropChance,
  totalRelativeDropChanceBonusPercent,
} from '../loot/dropChance'
import type { ActionRow, GameDatabase, RewardEntryRow } from '../data/types'
import { applyRaceGoldGain } from '../races/races'
import { activeSpellItemDoubleChancePercent } from '../spells/spells'
import type { PlayerSave } from '../save/types'
import type { LootGrant } from './types'
import type { RandomFn } from './pools'

function rollQuantity(entry: RewardEntryRow, random: RandomFn): number {
  const min = Math.max(0, Number(entry['Minimum Quantity'] ?? 1))
  const max = Math.max(min, Number(entry['Maximum Quantity'] ?? min))
  if (max === min) return min
  return min + Math.floor(random() * (max - min + 1))
}

export function pickWeightedReward(
  entries: RewardEntryRow[],
  random: RandomFn,
): RewardEntryRow | null {
  const usable = entries.filter(
    (entry) => entry.Status !== 'Needs Data' && typeof entry.Weight === 'number' && entry.Weight > 0,
  )
  if (usable.length === 0) return null
  const total = usable.reduce((sum, entry) => sum + (entry.Weight ?? 0), 0)
  let roll = random() * total
  for (const entry of usable) {
    roll -= entry.Weight ?? 0
    if (roll <= 0) return entry
  }
  return usable[usable.length - 1] ?? null
}

/**
 * Add as many as fit without exceeding the 180-slot bag or MAX_SAFE_INTEGER stacks.
 * Gold currency items are converted into `save.gold` instead of bag slots.
 * Returns how many were actually added (may be less than requested).
 */
export function addItemsToInventory(
  save: PlayerSave,
  itemId: string,
  quantity: number,
  enchantmentId: string | null = null,
  favorite = false,
): { save: PlayerSave; added: number } {
  const want = Math.floor(quantity)
  if (want <= 0) return { save, added: 0 }

  if (isGoldCurrencyItem(itemId) && !enchantmentId) {
    return {
      save: { ...save, gold: save.gold + want },
      added: want,
    }
  }

  const addable = maxAddableQuantity(save, itemId, enchantmentId, favorite)
  const added = Math.min(want, addable)
  if (added <= 0) return { save, added: 0 }

  const inventory = save.inventory.map((stack) => ({ ...stack }))

  if (enchantmentId) {
    for (let i = 0; i < added; i += 1) {
      inventory.push({
        itemId,
        quantity: 1,
        enchantmentId,
        ...(favorite ? { favorite: true } : {}),
      })
    }
    return { save: sortInventoryFavoritesFirst({ ...save, inventory }), added }
  }

  const existing = inventory.find(
    (stack) =>
      stack.itemId === itemId &&
      !stack.enchantmentId &&
      Boolean(stack.favorite) === favorite,
  )
  if (existing) {
    existing.quantity = Math.min(INVENTORY_STACK_MAX, existing.quantity + added)
  } else {
    inventory.push({
      itemId,
      quantity: added,
      ...(favorite ? { favorite: true } : {}),
    })
  }
  return { save: sortInventoryFavoritesFirst({ ...save, inventory }), added }
}

/** Convenience wrapper — adds only what fits (never overflows slots/stacks). */
export function addItemToInventory(
  save: PlayerSave,
  itemId: string,
  quantity: number,
  enchantmentId: string | null = null,
  favorite = false,
): PlayerSave {
  return addItemsToInventory(save, itemId, quantity, enchantmentId, favorite).save
}

/** Add the full quantity or fail without changing the save. */
export function addItemToInventoryExact(
  save: PlayerSave,
  itemId: string,
  quantity: number,
  enchantmentId: string | null = null,
  favorite = false,
): { ok: true; save: PlayerSave } | { ok: false; reason: string } {
  const want = Math.floor(quantity)
  if (want <= 0) return { ok: true, save }
  if (isGoldCurrencyItem(itemId) && !enchantmentId) {
    return { ok: true, save: addItemsToInventory(save, itemId, want).save }
  }
  if (!canFitItemQuantity(save, itemId, want, enchantmentId, favorite)) {
    if (save.inventory.length >= INVENTORY_SLOT_LIMIT) {
      return { ok: false, reason: 'Inventory is full (180 slots).' }
    }
    return { ok: false, reason: 'That stack cannot hold more of this item.' }
  }
  const result = addItemsToInventory(save, itemId, want, enchantmentId, favorite)
  if (result.added < want) {
    return { ok: false, reason: 'Inventory is full (180 slots).' }
  }
  return { ok: true, save: result.save }
}

export function resolveActionRewards(
  db: GameDatabase,
  save: PlayerSave,
  action: ActionRow,
  random: RandomFn = Math.random,
): { save: PlayerSave; loot: LootGrant[]; goldGained: number } {
  let next = save
  const loot: LootGrant[] = []
  let goldGained = Number(action['Guaranteed Gold'] ?? 0)

  const rollTable = (tableId: string | null, chance: number | null) => {
    if (!tableId) return
    const dropChance = applyRelativeDropChance(
      typeof chance === 'number' ? chance : 100,
      totalRelativeDropChanceBonusPercent(db, save),
    )
    if (typeof dropChance !== 'number' || random() * 100 >= dropChance) return
    const entries = db.RewardEntries.filter((row) => row['Reward Table ID'] === tableId)
    const picked = pickWeightedReward(entries, random)
    if (!picked) return
    if (picked['Reward Type'] === 'Item' && picked['Reward ID / Value']) {
      let quantity = rollQuantity(picked, random)
      const itemId = picked['Reward ID / Value']
      if (isGoldCurrencyItem(itemId)) {
        // Abundance doubles item drops only — gold currency item rewards stay single.
        goldGained += quantity
        return
      }
      const doubleChance = activeSpellItemDoubleChancePercent(db, save)
      if (doubleChance > 0 && random() * 100 < doubleChance) {
        quantity *= 2
      }
      const granted = addItemsToInventory(next, itemId, quantity)
      next = granted.save
      if (granted.added > 0) {
        loot.push({
          itemId,
          quantity: granted.added,
          displayName:
            db.Items.find((item) => item['Item ID'] === itemId)?.['Display Name'] ?? itemId,
        })
      }
    } else if (picked['Reward Type'] === 'Gold' || picked['Reward Type'] === 'Currency') {
      goldGained += rollQuantity(picked, random)
    }
  }

  rollTable(action['Reward Table ID'], action['Drop Chance'])
  rollTable(action['Secondary Reward Table ID'], action['Secondary Drop Chance'])

  goldGained = applyRaceGoldGain(db, save, goldGained)
  if (goldGained > 0) {
    next = { ...next, gold: next.gold + goldGained }
  }

  return { save: next, loot, goldGained }
}
