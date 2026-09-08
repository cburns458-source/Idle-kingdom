import { addItemsToInventory } from '../activity/rewards'
import { applyXp, getSkillProgress } from '../activity/xp'
import { creditLootTracker, creditXpAwards } from '../trackers/trackers'
import type { GameDatabase, ItemRow } from '../data/types'
import { removeIngredients } from '../production/inventory'
import { getQuestProgress } from '../quests/quests'
import type { LocationTimer, PlayerSave } from '../save/types'

export const BOTANY_SKILL_ID = 'SKL-0014'
export const THIEVERY_SKILL_ID = 'SKL-0015'
export const GLOVES_SLOT_ID = 'SLOT-0007'
export const COURTYARD_LOCATION_ID = 'LOC-0014'
export const GRAND_FEAST_QUEST_ID = 'QST-0001'
export const SHALLOWS_LOCATION_ID = 'LOC-0043'

export const HUNTING_TRAP_ITEM_ID = 'ITEM-0346'
export const FISHING_TRAP_ITEM_ID = 'ITEM-0347'

/** Botany patches: Farm, Courtyard, Gathering Outskirts, Mountains, Shallows, Temple, Meadow. */
export const BOTANY_PATCH_LOCATIONS = new Set([
  'LOC-0001',
  'LOC-0014',
  'LOC-0031',
  'LOC-0006',
  'LOC-0043',
  'LOC-0036',
  'LOC-0009',
])

export const HUNTING_TRAP_LOCATIONS = new Set(['LOC-0008', 'LOC-0009'])
export const FISHING_TRAP_LOCATIONS = new Set(['LOC-0003', 'LOC-0004'])

/** Default trap soak time: 6 hours. */
export const TRAP_DURATION_MS = 6 * 60 * 60 * 1000

export interface BotanySeedSpec {
  outputItemId: string
  growSeconds: number
  xp: number
  requiresLevel: number
  shallowsOnly: boolean
  isSapling: boolean
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
  const requiresLevel = Number(/RequiresLevel:(\d+)/i.exec(notes)?.[1] ?? 1)
  if (!output || grow <= 0) return null
  const tags = itemTags(item)
  return {
    outputItemId: output,
    growSeconds: grow,
    xp: Math.max(0, xp),
    requiresLevel: requiresLevel < 1 ? 1 : requiresLevel,
    shallowsOnly: /ShallowsOnly/i.test(notes) || tags.includes('shallows_only'),
    isSapling: tags.includes('botany_sapling'),
  }
}

export function inventoryHasAnyBotanySeed(db: GameDatabase, save: PlayerSave): boolean {
  return save.inventory.some((stack) => stack.quantity > 0 && isBotanySeedItem(db, stack.itemId))
}

export interface PlantableBotanyOption {
  itemId: string
  displayName: string
  spec: BotanySeedSpec
  owned: number
  plantQuantity: number
  canPlant: boolean
  reason: string
}

/** Seeds/saplings the player owns that could be offered on a patch menu. */
export function listPlantableBotanyOptions(
  db: GameDatabase,
  save: PlayerSave,
  locationId: string = save.currentLocationId,
): PlantableBotanyOption[] {
  const options: PlantableBotanyOption[] = []
  const seen = new Set<string>()
  for (const stack of save.inventory) {
    if (stack.quantity <= 0) continue
    if (seen.has(stack.itemId)) continue
    seen.add(stack.itemId)
    const spec = parseBotanySeedSpec(db, stack.itemId)
    if (!spec) continue
    const owned = save.inventory
      .filter((row) => row.itemId === stack.itemId)
      .reduce((sum, row) => sum + row.quantity, 0)
    const desired = spec.isSapling ? 1 : Math.min(3, owned)
    const gate = canPlantBotanySeed(db, save, stack.itemId, locationId, desired)
    options.push({
      itemId: stack.itemId,
      displayName: itemById(db, stack.itemId)?.['Display Name'] ?? stack.itemId,
      spec,
      owned,
      plantQuantity: gate.ok ? gate.quantity : desired,
      canPlant: gate.ok,
      reason: gate.ok ? '' : gate.reason,
    })
  }
  options.sort((a, b) => {
    const level = a.spec.requiresLevel - b.spec.requiresLevel
    if (level !== 0) return level
    return a.displayName.localeCompare(b.displayName)
  })
  return options
}

/** Any timer at a location (first match). Prefer [timerAtLocationKind] when kind matters. */
export function timerAtLocation(
  save: PlayerSave,
  locationId: string,
): LocationTimer | undefined {
  return (save.locationTimers ?? []).find((timer) => timer.locationId === locationId)
}

export type TimerSpotKind = 'botany' | 'hunting_trap' | 'fishing_trap'

/** Timer matching both location and kind (at most one of each kind per spot). */
export function timerAtLocationKind(
  save: PlayerSave,
  locationId: string,
  kind: TimerSpotKind | string,
): LocationTimer | undefined {
  return (save.locationTimers ?? []).find(
    (timer) => timer.locationId === locationId && timer.kind === kind,
  )
}

function withoutLocationTimerKind(
  timers: LocationTimer[] | undefined,
  locationId: string,
  kind: string,
): LocationTimer[] {
  return (timers ?? []).filter(
    (row) => !(row.locationId === locationId && row.kind === kind),
  )
}

/** Stable key for a timer spot in `discoveredTimerSpotIds`. */
export function timerSpotKey(kind: TimerSpotKind, locationId: string): string {
  return `${kind}:${locationId}`
}

/** Split a spot key back into kind + location, or null if malformed. */
export function parseTimerSpotKey(
  key: string,
): { kind: TimerSpotKind; locationId: string } | null {
  const sep = key.indexOf(':')
  if (sep <= 0) return null
  const kind = key.slice(0, sep)
  const locationId = key.slice(sep + 1)
  if (!locationId) return null
  if (kind !== 'botany' && kind !== 'hunting_trap' && kind !== 'fishing_trap') return null
  return { kind, locationId }
}

/**
 * Marks Botany / hunting / fishing spots at [locationId] as discovered when the
 * location supports them. Safe to call on plant, place, or travel arrival.
 */
export function discoverTimerSpotsForLocation(
  save: PlayerSave,
  locationId: string,
): PlayerSave {
  const discovered = new Set(save.discoveredTimerSpotIds ?? [])
  let changed = false
  const add = (kind: TimerSpotKind) => {
    const key = timerSpotKey(kind, locationId)
    if (discovered.has(key)) return
    discovered.add(key)
    changed = true
  }
  if (BOTANY_PATCH_LOCATIONS.has(locationId)) add('botany')
  if (HUNTING_TRAP_LOCATIONS.has(locationId)) add('hunting_trap')
  if (FISHING_TRAP_LOCATIONS.has(locationId)) add('fishing_trap')
  if (!changed) return save
  return { ...save, discoveredTimerSpotIds: [...discovered] }
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

export function locationHasBotanyPatch(locationId: string): boolean {
  return BOTANY_PATCH_LOCATIONS.has(locationId)
}

export function canPlantBotanySeed(
  db: GameDatabase,
  save: PlayerSave,
  seedItemId: string,
  locationId: string = save.currentLocationId,
  plantQuantity: number = 1,
): { ok: true; quantity: number } | { ok: false; quantity: number; reason: string } {
  if (!locationHasBotanyPatch(locationId)) {
    return { ok: false, quantity: 0, reason: 'There is no Botany patch here.' }
  }
  if (locationId === COURTYARD_LOCATION_ID && !courtyardBotanyUnlocked(save)) {
    return {
      ok: false,
      quantity: 0,
      reason: 'Complete The Grand Feast to unlock the Courtyard plot.',
    }
  }
  if (timerAtLocationKind(save, locationId, 'botany')) {
    return { ok: false, quantity: 0, reason: 'This patch is already growing.' }
  }
  const spec = parseBotanySeedSpec(db, seedItemId)
  if (!spec) {
    return { ok: false, quantity: 0, reason: 'That item cannot be planted.' }
  }
  if (spec.shallowsOnly && locationId !== SHALLOWS_LOCATION_ID) {
    return { ok: false, quantity: 0, reason: 'Kelp only grows in The Shallows.' }
  }
  if (!spec.shallowsOnly && locationId === SHALLOWS_LOCATION_ID) {
    return { ok: false, quantity: 0, reason: 'The Shallows plot only accepts kelp.' }
  }
  const botanyLevel = getSkillProgress(save, BOTANY_SKILL_ID).level
  if (botanyLevel < spec.requiresLevel) {
    return {
      ok: false,
      quantity: 0,
      reason: `Requires Botany level ${spec.requiresLevel}.`,
    }
  }
  const have = save.inventory
    .filter((stack) => stack.itemId === seedItemId)
    .reduce((sum, stack) => sum + stack.quantity, 0)
  if (have < 1) return { ok: false, quantity: 0, reason: 'You do not have that seed.' }
  const maxQty = spec.isSapling ? 1 : 3
  let quantity = Math.floor(plantQuantity)
  if (quantity > maxQty) quantity = maxQty
  if (quantity > Math.floor(have)) quantity = Math.floor(have)
  if (quantity < 1) quantity = 1
  if (spec.isSapling && quantity !== 1) {
    return { ok: false, quantity: 0, reason: 'A patch holds one sapling.' }
  }
  return { ok: true, quantity }
}

export function plantBotanySeed(
  db: GameDatabase,
  save: PlayerSave,
  seedItemId: string,
  nowMs: number = Date.now(),
  plantQuantity: number = 3,
): { ok: true; save: PlayerSave } | { ok: false; reason: string } {
  const locationId = save.currentLocationId
  const gate = canPlantBotanySeed(db, save, seedItemId, locationId, plantQuantity)
  if (!gate.ok) return { ok: false, reason: gate.reason }
  const spec = parseBotanySeedSpec(db, seedItemId)!
  const removed = removeIngredients(save, [{ itemId: seedItemId, quantity: gate.quantity }])
  if (!removed) return { ok: false, reason: 'You do not have that seed.' }
  const timer: LocationTimer = {
    locationId,
    kind: 'botany',
    inputItemId: seedItemId,
    outputItemId: spec.outputItemId,
    // Planted count; yield is rolled on collect.
    outputQuantity: gate.quantity,
    skillId: BOTANY_SKILL_ID,
    xpReward: spec.xp * gate.quantity,
    startedAt: new Date(nowMs).toISOString(),
    durationMs: spec.growSeconds * 1000,
  }
  return {
    ok: true,
    save: discoverTimerSpotsForLocation(
      {
        ...removed,
        locationTimers: [
          ...withoutLocationTimerKind(removed.locationTimers, locationId, 'botany'),
          timer,
        ],
      },
      locationId,
    ),
  }
}

export function plantBestBotanySeed(
  db: GameDatabase,
  save: PlayerSave,
  nowMs: number = Date.now(),
): { ok: true; save: PlayerSave } | { ok: false; reason: string } {
  for (const stack of save.inventory) {
    if (stack.quantity <= 0) continue
    const spec = parseBotanySeedSpec(db, stack.itemId)
    if (!spec) continue
    const qty = spec.isSapling ? 1 : Math.min(3, stack.quantity)
    const planted = plantBotanySeed(db, save, stack.itemId, nowMs, qty)
    if (planted.ok) return planted
  }
  return {
    ok: false,
    reason: 'You have no plantable seeds or saplings for this patch.',
  }
}

export function canPlaceTrap(
  _db: GameDatabase,
  save: PlayerSave,
  trapItemId: string,
  locationId: string = save.currentLocationId,
): { ok: true; kind: 'hunting_trap' | 'fishing_trap' } | { ok: false; reason: string } {
  if (trapItemId === HUNTING_TRAP_ITEM_ID) {
    if (!HUNTING_TRAP_LOCATIONS.has(locationId)) {
      return { ok: false, reason: 'Hunting traps only work in the Kingswoods and Meadow.' }
    }
    if (timerAtLocationKind(save, locationId, 'hunting_trap')) {
      return { ok: false, reason: 'A hunting trap is already set here.' }
    }
    const have = save.inventory.find((stack) => stack.itemId === trapItemId)?.quantity ?? 0
    if (have < 1) return { ok: false, reason: 'You do not have that trap.' }
    return { ok: true, kind: 'hunting_trap' }
  }
  if (trapItemId === FISHING_TRAP_ITEM_ID) {
    if (!FISHING_TRAP_LOCATIONS.has(locationId)) {
      return { ok: false, reason: 'Fishing traps only work at the Goblin Camp and Docks.' }
    }
    if (timerAtLocationKind(save, locationId, 'fishing_trap')) {
      return { ok: false, reason: 'A fishing trap is already set here.' }
    }
    const have = save.inventory.find((stack) => stack.itemId === trapItemId)?.quantity ?? 0
    if (have < 1) return { ok: false, reason: 'You do not have that trap.' }
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
    save: discoverTimerSpotsForLocation(
      {
        ...removed,
        locationTimers: [
          ...withoutLocationTimerKind(removed.locationTimers, locationId, gate.kind),
          timer,
        ],
      },
      locationId,
    ),
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

function rollInclusive(random: () => number, min: number, max: number): number {
  return min + Math.floor(random() * (max - min + 1))
}

export function collectLocationTimer(
  db: GameDatabase,
  save: PlayerSave,
  locationId: string,
  kind: TimerSpotKind | string,
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
  const timer = timerAtLocationKind(save, locationId, kind)
  if (!timer) return { ok: false, reason: 'No timer at this location.' }
  if (!timerIsReady(timer, nowMs)) {
    const remainSec = Math.ceil((timerCompletesAtMs(timer) - nowMs) / 1000)
    return { ok: false, reason: `Not ready yet (${remainSec}s left).` }
  }

  let next: PlayerSave = {
    ...save,
    locationTimers: withoutLocationTimerKind(save.locationTimers, locationId, kind),
  }
  const loot: Array<{ itemId: string; quantity: number; displayName: string }> = []
  let xpGained = timer.xpReward
  const skillId = timer.skillId

  if (timer.kind === 'botany') {
    if (!timer.outputItemId) return { ok: false, reason: 'Botany timer is missing its crop.' }
    const planted = timer.outputQuantity > 0 ? Math.round(timer.outputQuantity) : 1
    const plantedCount = planted < 1 ? 1 : planted
    let produceQty = 0
    for (let i = 0; i < plantedCount; i += 1) {
      produceQty += rollInclusive(random, 1, 5)
    }
    const granted = addItemsToInventory(next, timer.outputItemId, produceQty, null, false, db)
    next = granted.save
    loot.push({
      itemId: timer.outputItemId,
      quantity: produceQty,
      displayName:
        db.Items.find((item) => item['Item ID'] === timer.outputItemId)?.['Display Name'] ??
        timer.outputItemId,
    })
    let returned = 0
    for (let i = 0; i < plantedCount; i += 1) {
      if (random() < 0.5) returned += 1
    }
    if (returned > 0) {
      const back = addItemsToInventory(next, timer.inputItemId, returned, null, false, db)
      next = back.save
      loot.push({
        itemId: timer.inputItemId,
        quantity: returned,
        displayName:
          db.Items.find((item) => item['Item ID'] === timer.inputItemId)?.['Display Name'] ??
          timer.inputItemId,
      })
    }
  } else {
    const rolled = rollTrapLoot(timer.locationId, random)
    if (rolled) {
      const granted = addItemsToInventory(next, rolled.itemId, 1, null, false, db)
      next = granted.save
      xpGained = rolled.xp
      loot.push({
        itemId: rolled.itemId,
        quantity: 1,
        displayName:
          db.Items.find((item) => item['Item ID'] === rolled.itemId)?.['Display Name'] ??
          rolled.itemId,
      })
    }
    // Return the trap so it can be placed again.
    next = addItemsToInventory(next, timer.inputItemId, 1, null, false, db).save
  }

  next = applyXp(next, db, skillId, xpGained).save
  next = creditLootTracker(next, 'timer', `${kind}:${locationId}`, loot, 0, nowMs)
  next = creditXpAwards(next, [{ skillId, xp: xpGained }], nowMs)

  return { ok: true, save: next, loot, xpGained, skillId }
}
