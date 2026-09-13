import { addItemsToInventory } from '../activity/rewards'
import { applyXp, getSkillProgress } from '../activity/xp'
import { canFitItemQuantity } from '../inventory/capacity'
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

export const FISHING_POT_ITEM_ID = 'ITEM-0347'
/** @deprecated Use FISHING_POT_ITEM_ID */
export const FISHING_TRAP_ITEM_ID = FISHING_POT_ITEM_ID

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

export const FISHING_POT_LOCATIONS = new Set(['LOC-0003', 'LOC-0004'])
/** @deprecated Use FISHING_POT_LOCATIONS */
export const FISHING_TRAP_LOCATIONS = FISHING_POT_LOCATIONS

/** Default trap soak time: 6 hours. */
export const TRAP_DURATION_MS = 6 * 60 * 60 * 1000

/** Ready timers stay in place when the bag cannot take the haul. */
export const TIMER_INVENTORY_FULL_REASON =
  'Come back with more room to collect your harvest/catch.'

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

export type TimerSpotKind = 'botany' | 'fishing_pot'

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
  if (kind !== 'botany' && kind !== 'fishing_pot') return null
  return { kind, locationId }
}

/**
 * Marks Botany / fishing pot spots at [locationId] as discovered when the
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
  if (FISHING_POT_LOCATIONS.has(locationId)) add('fishing_pot')
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

export function fishingPotUtcDayKey(nowMs: number): string {
  return new Date(nowMs).toISOString().slice(0, 10)
}

/** Ms until the next UTC midnight after `nowMs`. */
export function msUntilNextUtcDay(nowMs: number): number {
  const next = Date.UTC(
    new Date(nowMs).getUTCFullYear(),
    new Date(nowMs).getUTCMonth(),
    new Date(nowMs).getUTCDate() + 1,
  )
  return Math.max(0, next - nowMs)
}

export function fishingPotLockedUntilDay(
  save: PlayerSave,
  locationId: string,
  nowMs: number = Date.now(),
): { locked: boolean; dayKey: string; msRemaining: number } {
  const dayKey = fishingPotUtcDayKey(nowMs)
  const used = save.fishingPotDayKeyByLocationId?.[locationId]
  if (used === dayKey) {
    return { locked: true, dayKey, msRemaining: msUntilNextUtcDay(nowMs) }
  }
  return { locked: false, dayKey, msRemaining: 0 }
}

export function canPlaceTrap(
  _db: GameDatabase,
  save: PlayerSave,
  trapItemId: string,
  locationId: string = save.currentLocationId,
  nowMs: number = Date.now(),
): { ok: true; kind: 'fishing_pot' } | { ok: false; reason: string } {
  void _db
  if (trapItemId === FISHING_POT_ITEM_ID) {
    if (!FISHING_POT_LOCATIONS.has(locationId)) {
      return { ok: false, reason: 'Fishing pots only work at the Goblin Camp and Docks.' }
    }
    if (timerAtLocationKind(save, locationId, 'fishing_pot')) {
      return { ok: false, reason: 'A fishing pot is already set here.' }
    }
    const lock = fishingPotLockedUntilDay(save, locationId, nowMs)
    if (lock.locked) {
      return {
        ok: false,
        reason: 'You should not overfish. Come back after the daily reset.',
      }
    }
    const fishingLevel = getSkillProgress(save, 'SKL-0003').level
    const unlocked = potFishOptionsForLocation(locationId, fishingLevel)
    if (unlocked.length === 0) {
      const need = locationId === 'LOC-0004' ? 35 : 14
      return {
        ok: false,
        reason: `You need Fishing ${need} before this pot will catch anything.`,
      }
    }
    const have = save.inventory.find((stack) => stack.itemId === trapItemId)?.quantity ?? 0
    if (have < 1) return { ok: false, reason: 'You do not have a fishing pot.' }
    return { ok: true, kind: 'fishing_pot' }
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
  const gate = canPlaceTrap(db, save, trapItemId, locationId, nowMs)
  if (!gate.ok) return gate
  const removed = removeIngredients(save, [{ itemId: trapItemId, quantity: 1 }])
  if (!removed) {
    return { ok: false, reason: 'You do not have a fishing pot.' }
  }
  const timer: LocationTimer = {
    locationId,
    kind: gate.kind,
    inputItemId: trapItemId,
    outputItemId: null,
    outputQuantity: 1,
    skillId: 'SKL-0003',
    xpReward: 150,
    startedAt: new Date(nowMs).toISOString(),
    durationMs: TRAP_DURATION_MS,
  }
  const next: PlayerSave = {
    ...removed,
    locationTimers: [
      ...withoutLocationTimerKind(removed.locationTimers, locationId, gate.kind),
      timer,
    ],
    fishingPotDayKeyByLocationId: {
      ...(removed.fishingPotDayKeyByLocationId ?? {}),
      [locationId]: fishingPotUtcDayKey(nowMs),
    },
  }
  return {
    ok: true,
    save: discoverTimerSpotsForLocation(next, locationId),
  }
}

function rollInclusive(random: () => number, min: number, max: number): number {
  return min + Math.floor(random() * (max - min + 1))
}

/** Pot-fishing catches: Goblin Camp freshwater vs Docks saltwater. */
export const POT_FISH_BY_LOCATION: Record<
  string,
  Array<{ itemId: string; fishingLevel: number; xpEach: number }>
> = {
  'LOC-0003': [
    { itemId: 'ITEM-0352', fishingLevel: 14, xpEach: 150 },
    { itemId: 'ITEM-0354', fishingLevel: 44, xpEach: 350 },
    { itemId: 'ITEM-0356', fishingLevel: 64, xpEach: 520 },
  ],
  'LOC-0004': [
    { itemId: 'ITEM-0353', fishingLevel: 35, xpEach: 280 },
    { itemId: 'ITEM-0355', fishingLevel: 55, xpEach: 450 },
    { itemId: 'ITEM-0357', fishingLevel: 75, xpEach: 650 },
  ],
}

export function potFishOptionsForLocation(
  locationId: string,
  fishingLevel: number,
): Array<{ itemId: string; fishingLevel: number; xpEach: number }> {
  return (POT_FISH_BY_LOCATION[locationId] ?? []).filter((row) => fishingLevel >= row.fishingLevel)
}

function rollFishingPotLoot(
  locationId: string,
  fishingLevel: number,
  random: () => number,
): Array<{ itemId: string; quantity: number; xp: number }> {
  return potFishOptionsForLocation(locationId, fishingLevel).map((row) => {
    const quantity = rollInclusive(random, 1, 3)
    return { itemId: row.itemId, quantity, xp: row.xpEach * quantity }
  })
}

function timerItemName(db: GameDatabase, itemId: string): string {
  return db.Items.find((item) => item['Item ID'] === itemId)?.['Display Name'] ?? itemId
}

function canFitTimerGrants(
  save: PlayerSave,
  grants: Array<{ itemId: string; quantity: number }>,
  db: GameDatabase,
): boolean {
  let probe = save
  for (const grant of grants) {
    if (!canFitItemQuantity(probe, grant.itemId, grant.quantity, null, false, db)) return false
    probe = addItemsToInventory(probe, grant.itemId, grant.quantity, null, false, db).save
  }
  return true
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

  const grants: Array<{ itemId: string; quantity: number }> = []
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
    grants.push({ itemId: timer.outputItemId, quantity: produceQty })
    let returned = 0
    for (let i = 0; i < plantedCount; i += 1) {
      if (random() < 0.5) returned += 1
    }
    if (returned > 0) grants.push({ itemId: timer.inputItemId, quantity: returned })
  } else if (timer.kind === 'fishing_pot') {
    const fishingLevel = getSkillProgress(save, 'SKL-0003').level
    const rolled = rollFishingPotLoot(timer.locationId, fishingLevel, random)
    xpGained = 0
    for (const row of rolled) {
      grants.push({ itemId: row.itemId, quantity: row.quantity })
      xpGained += row.xp
    }
    grants.push({ itemId: timer.inputItemId, quantity: 1 })
  } else {
    return { ok: false, reason: 'Unknown timer kind.' }
  }

  if (!canFitTimerGrants(save, grants, db)) {
    return { ok: false, reason: TIMER_INVENTORY_FULL_REASON }
  }

  let next: PlayerSave = {
    ...save,
    locationTimers: withoutLocationTimerKind(save.locationTimers, locationId, kind),
  }
  const loot: Array<{ itemId: string; quantity: number; displayName: string }> = []
  for (const grant of grants) {
    next = addItemsToInventory(next, grant.itemId, grant.quantity, null, false, db).save
    loot.push({
      itemId: grant.itemId,
      quantity: grant.quantity,
      displayName: timerItemName(db, grant.itemId),
    })
  }

  next = applyXp(next, db, skillId, xpGained).save
  next = creditLootTracker(next, 'timer', `${kind}:${locationId}`, loot, 0, nowMs)
  next = creditXpAwards(next, [{ skillId, xp: xpGained }], nowMs)

  return { ok: true, save: next, loot, xpGained, skillId }
}
