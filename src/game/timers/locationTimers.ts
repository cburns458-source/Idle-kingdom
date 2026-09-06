import { addItemsToInventory } from '../activity/rewards'
import { applyXp } from '../activity/xp'
import type { GameDatabase, ItemRow } from '../data/types'
import { removeIngredients } from '../production/inventory'
import { getQuestProgress } from '../quests/quests'
import type { LocationTimer, PlayerSave } from '../save/types'

export const BOTANY_SKILL_ID = 'SKL-0014'
export const THIEVERY_SKILL_ID = 'SKL-0015'
export const GLOVES_SLOT_ID = 'SLOT-0007'
export const COURTYARD_LOCATION_ID = 'LOC-0014'
export const GRAND_FEAST_QUEST_ID = 'QST-0001'

export const HUNTING_TRAP_ITEM_ID = 'ITEM-0346'
export const FISHING_TRAP_ITEM_ID = 'ITEM-0347'

export const HUNTING_TRAP_LOCATIONS = new Set(['LOC-0008', 'LOC-0009'])
export const FISHING_TRAP_LOCATIONS = new Set(['LOC-0003', 'LOC-0004'])

/** Default trap soak time: 5 minutes. */
export const TRAP_DURATION_MS = 5 * 60 * 1000

export interface BotanySeedSpec {
  outputItemId: string
  growSeconds: number
  xp: number
}

function itemById(db: GameDatabase, itemId: string): ItemRow | undefined {
  return db.Items.find((row) => row['Item ID'] === itemId)
}

function itemTags(item: ItemRow | undefined): string {
  return (item?.['Functional / Source Tags'] ?? '').toLowerCase()
}

export function isBotanySeedItem(db: GameDatabase, itemId: string): boolean {
  const tags = itemTags(itemById(db, itemId))
  return tags.includes('botany_seed') || tags.includes('botany_sapling')
}

export function parseBotanySeedSpec(db: GameDatabase, itemId: string): BotanySeedSpec | null {
  const item = itemById(db, itemId)
  if (!item || !isBotanySeedItem(db, itemId)) return null
  const notes = item.Notes ?? ''
  const output = /Output:([A-Z0-9-]+)/i.exec(notes)?.[1]
  const grow = Number(/GrowSeconds:(\d+)/i.exec(notes)?.[1] ?? 0)
  const xp = Number(/Xp:(\d+)/i.exec(notes)?.[1] ?? 0)
  if (!output || grow <= 0) return null
  return { outputItemId: output, growSeconds: grow, xp: Math.max(0, xp) }
}

export function inventoryHasAnyBotanySeed(db: GameDatabase, save: PlayerSave): boolean {
  return save.inventory.some((stack) => stack.quantity > 0 && isBotanySeedItem(db, stack.itemId))
}

export function timerAtLocation(
  save: PlayerSave,
  locationId: string,
): LocationTimer | undefined {
  return (save.locationTimers ?? []).find((timer) => timer.locationId === locationId)
}

export function timerCompletesAtMs(timer: LocationTimer): number {
  return Date.parse(timer.startedAt) + timer.durationMs
}

export function timerIsReady(timer: LocationTimer, nowMs: number = Date.now()): boolean {
  return nowMs >= timerCompletesAtMs(timer)
}

export function courtyardBotanyUnlocked(save: PlayerSave): boolean {
  return getQuestProgress(save, GRAND_FEAST_QUEST_ID).status === 'completed'
}

export function canPlantBotanySeed(
  db: GameDatabase,
  save: PlayerSave,
  seedItemId: string,
  locationId: string = save.currentLocationId,
): { ok: true } | { ok: false; reason: string } {
  if (locationId !== COURTYARD_LOCATION_ID) {
    return { ok: false, reason: 'Botany plots are only in the Courtyard.' }
  }
  if (!courtyardBotanyUnlocked(save)) {
    return { ok: false, reason: 'Complete The Grand Feast to unlock the Courtyard plot.' }
  }
  if (timerAtLocation(save, locationId)) {
    return { ok: false, reason: 'This location already has a timer running.' }
  }
  if (!parseBotanySeedSpec(db, seedItemId)) {
    return { ok: false, reason: 'That item cannot be planted.' }
  }
  const have = save.inventory.find((stack) => stack.itemId === seedItemId)?.quantity ?? 0
  if (have < 1) return { ok: false, reason: 'You do not have that seed.' }
  return { ok: true }
}

export function plantBotanySeed(
  db: GameDatabase,
  save: PlayerSave,
  seedItemId: string,
  nowMs: number = Date.now(),
): { ok: true; save: PlayerSave } | { ok: false; reason: string } {
  const locationId = save.currentLocationId
  const gate = canPlantBotanySeed(db, save, seedItemId, locationId)
  if (!gate.ok) return gate
  const spec = parseBotanySeedSpec(db, seedItemId)!
  const removed = removeIngredients(save, [{ itemId: seedItemId, quantity: 1 }])
  if (!removed) return { ok: false, reason: 'You do not have that seed.' }
  const timer: LocationTimer = {
    locationId,
    kind: 'botany',
    inputItemId: seedItemId,
    outputItemId: spec.outputItemId,
    outputQuantity: 1,
    skillId: BOTANY_SKILL_ID,
    xpReward: spec.xp,
    startedAt: new Date(nowMs).toISOString(),
    durationMs: spec.growSeconds * 1000,
  }
  return {
    ok: true,
    save: {
      ...removed,
      locationTimers: [
        ...(removed.locationTimers ?? []).filter((row) => row.locationId !== locationId),
        timer,
      ],
    },
  }
}


export function plantBestBotanySeed(
  db: GameDatabase,
  save: PlayerSave,
  nowMs: number = Date.now(),
): { ok: true; save: PlayerSave } | { ok: false; reason: string } {
  for (const stack of save.inventory) {
    if (stack.quantity <= 0) continue
    if (!parseBotanySeedSpec(db, stack.itemId)) continue
    return plantBotanySeed(db, save, stack.itemId, nowMs)
  }
  return { ok: false, reason: 'You have no plantable seeds or saplings.' }
}

export function canPlaceTrap(
  _db: GameDatabase,
  save: PlayerSave,
  trapItemId: string,
  locationId: string = save.currentLocationId,
): { ok: true; kind: 'hunting_trap' | 'fishing_trap' } | { ok: false; reason: string } {
  if (timerAtLocation(save, locationId)) {
    return { ok: false, reason: 'This location already has a timer running.' }
  }
  const have = save.inventory.find((stack) => stack.itemId === trapItemId)?.quantity ?? 0
  if (have < 1) return { ok: false, reason: 'You do not have that trap.' }
  if (trapItemId === HUNTING_TRAP_ITEM_ID) {
    if (!HUNTING_TRAP_LOCATIONS.has(locationId)) {
      return { ok: false, reason: 'Hunting traps only work in the Kingswoods and Meadow.' }
    }
    return { ok: true, kind: 'hunting_trap' }
  }
  if (trapItemId === FISHING_TRAP_ITEM_ID) {
    if (!FISHING_TRAP_LOCATIONS.has(locationId)) {
      return { ok: false, reason: 'Fishing traps only work at the Goblin Camp and Docks.' }
    }
    return { ok: true, kind: 'fishing_trap' }
  }
  return { ok: false, reason: 'That is not a placeable trap.' }
}

export function placeTrap(
  db: GameDatabase,
  save: PlayerSave,
  trapItemId: string,
  nowMs: number = Date.now(),
): { ok: true; save: PlayerSave } | { ok: false; reason: string } {
  const locationId = save.currentLocationId
  const gate = canPlaceTrap(db, save, trapItemId, locationId)
  if (!gate.ok) return gate
  const removed = removeIngredients(save, [{ itemId: trapItemId, quantity: 1 }])
  if (!removed) return { ok: false, reason: 'You do not have that trap.' }
  const skillId = gate.kind === 'hunting_trap' ? 'SKL-0005' : 'SKL-0003'
  const timer: LocationTimer = {
    locationId,
    kind: gate.kind,
    inputItemId: trapItemId,
    outputItemId: null,
    outputQuantity: 1,
    skillId,
    xpReward: gate.kind === 'hunting_trap' ? 200 : 150,
    startedAt: new Date(nowMs).toISOString(),
    durationMs: TRAP_DURATION_MS,
  }
  return {
    ok: true,
    save: {
      ...removed,
      locationTimers: [
        ...(removed.locationTimers ?? []).filter((row) => row.locationId !== locationId),
        timer,
      ],
    },
  }
}

/** Simple trap loot tables by location. */
const TRAP_LOOT: Record<string, Array<{ itemId: string; weight: number; xp: number }>> = {
  'LOC-0008': [
    { itemId: 'ITEM-0053', weight: 50, xp: 200 },
    { itemId: 'ITEM-0055', weight: 30, xp: 350 },
    { itemId: 'ITEM-0052', weight: 20, xp: 180 },
  ],
  'LOC-0009': [
    { itemId: 'ITEM-0052', weight: 45, xp: 180 },
    { itemId: 'ITEM-0193', weight: 45, xp: 180 },
    { itemId: 'ITEM-0053', weight: 10, xp: 200 },
  ],
  'LOC-0003': [
    { itemId: 'ITEM-0047', weight: 50, xp: 120 },
    { itemId: 'ITEM-0048', weight: 35, xp: 200 },
    { itemId: 'ITEM-0049', weight: 15, xp: 300 },
  ],
  'LOC-0004': [
    { itemId: 'ITEM-0050', weight: 40, xp: 350 },
    { itemId: 'ITEM-0049', weight: 35, xp: 300 },
    { itemId: 'ITEM-0048', weight: 25, xp: 200 },
  ],
}

function rollTrapLoot(
  locationId: string,
  random: () => number,
): { itemId: string; xp: number } | null {
  const table = TRAP_LOOT[locationId]
  if (!table || table.length === 0) return null
  const total = table.reduce((sum, row) => sum + row.weight, 0)
  let roll = random() * total
  for (const row of table) {
    roll -= row.weight
    if (roll <= 0) return { itemId: row.itemId, xp: row.xp }
  }
  const last = table[table.length - 1]!
  return { itemId: last.itemId, xp: last.xp }
}

export function collectLocationTimer(
  db: GameDatabase,
  save: PlayerSave,
  locationId: string,
  nowMs: number = Date.now(),
  random: () => number = Math.random,
):
  | {
      ok: true
      save: PlayerSave
      loot: Array<{ itemId: string; quantity: number; displayName: string }>
      xpGained: number
      skillId: string
    }
  | { ok: false; reason: string } {
  const timer = timerAtLocation(save, locationId)
  if (!timer) return { ok: false, reason: 'No timer at this location.' }
  if (!timerIsReady(timer, nowMs)) {
    const remainSec = Math.ceil((timerCompletesAtMs(timer) - nowMs) / 1000)
    return { ok: false, reason: `Not ready yet (${remainSec}s left).` }
  }

  let next: PlayerSave = {
    ...save,
    locationTimers: (save.locationTimers ?? []).filter((row) => row.locationId !== locationId),
  }
  const loot: Array<{ itemId: string; quantity: number; displayName: string }> = []
  let xpGained = timer.xpReward
  const skillId = timer.skillId

  if (timer.kind === 'botany') {
    if (!timer.outputItemId) return { ok: false, reason: 'Botany timer is missing its crop.' }
    const granted = addItemsToInventory(
      next,
      timer.outputItemId,
      timer.outputQuantity,
      null,
      false,
      db,
    )
    next = granted.save
    if (granted.added > 0) {
      loot.push({
        itemId: timer.outputItemId,
        quantity: granted.added,
        displayName:
          db.Items.find((item) => item['Item ID'] === timer.outputItemId)?.['Display Name'] ??
          timer.outputItemId,
      })
    }
  } else {
    const rolled = rollTrapLoot(locationId, random)
    if (rolled) {
      const granted = addItemsToInventory(next, rolled.itemId, 1, null, false, db)
      next = granted.save
      xpGained = rolled.xp
      if (granted.added > 0) {
        loot.push({
          itemId: rolled.itemId,
          quantity: granted.added,
          displayName:
            db.Items.find((item) => item['Item ID'] === rolled.itemId)?.['Display Name'] ??
            rolled.itemId,
        })
      }
    }
    // Return the trap so it can be placed again.
    next = addItemsToInventory(next, timer.inputItemId, 1, null, false, db).save
  }

  if (xpGained > 0) {
    next = applyXp(next, db, skillId, xpGained).save
  }

  return { ok: true, save: next, loot, xpGained, skillId }
}
