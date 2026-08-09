import type { ActionRow, GameDatabase, RewardEntryRow } from '../data/types'
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

export function addItemToInventory(
  save: PlayerSave,
  itemId: string,
  quantity: number,
): PlayerSave {
  if (quantity <= 0) return save
  const inventory = save.inventory.map((stack) => ({ ...stack }))
  const existing = inventory.find((stack) => stack.itemId === itemId)
  if (existing) {
    existing.quantity += quantity
  } else {
    inventory.push({ itemId, quantity })
  }
  return { ...save, inventory }
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
  if (goldGained > 0) {
    next = { ...next, gold: next.gold + goldGained }
  }

  const rollTable = (tableId: string | null, chance: number | null) => {
    if (!tableId) return
    const dropChance = typeof chance === 'number' ? chance : 100
    if (random() * 100 >= dropChance) return
    const entries = db.RewardEntries.filter((row) => row['Reward Table ID'] === tableId)
    const picked = pickWeightedReward(entries, random)
    if (!picked) return
    if (picked['Reward Type'] === 'Item' && picked['Reward ID / Value']) {
      const quantity = rollQuantity(picked, random)
      const itemId = picked['Reward ID / Value']
      next = addItemToInventory(next, itemId, quantity)
      loot.push({
        itemId,
        quantity,
        displayName: db.Items.find((item) => item['Item ID'] === itemId)?.['Display Name'] ?? itemId,
      })
    } else if (picked['Reward Type'] === 'Gold' || picked['Reward Type'] === 'Currency') {
      const quantity = rollQuantity(picked, random)
      goldGained += quantity
      next = { ...next, gold: next.gold + quantity }
    }
  }

  rollTable(action['Reward Table ID'], action['Drop Chance'])
  rollTable(action['Secondary Reward Table ID'], action['Secondary Drop Chance'])

  return { save: next, loot, goldGained }
}
