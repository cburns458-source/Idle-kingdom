import { addItemsToInventory } from '../activity/rewards'
import { applyXp, getSkillProgress } from '../activity/xp'
import { canFitItemQuantity } from '../inventory/capacity'
import { creditLootTracker, creditXpAwards } from '../trackers/trackers'
import type { GameDatabase, ItemRow } from '../data/types'
import { removeIngredients } from '../production/inventory'
import { applyQuestAutoStartOnSeed, applyQuestPlantProgress } from '../quests/progress'
import { applyQuestAutoCompleteOnPlant, getQuestProgress } from '../quests/quests'
import type { LocationTimer, PlayerSave } from '../save/types'

export const BOTANY_SKILL_ID = 'SKL-0014'
export const THIEVERY_SKILL_ID = 'SKL-0015'
export const GLOVES_SLOT_ID = 'SLOT-0007'
export const FARM_LOCATION_ID = 'LOC-0001'
export const COURTYARD_LOCATION_ID = 'LOC-0014'
export const GRAND_FEAST_QUEST_ID = 'QST-0001'
export const FIRST_PLANTING_QUEST_ID = 'QST-0011'
export const FENNEL_NPC_ID = 'NPC-0014'
export const POTATO_SEED_ITEM_ID = 'ITEM-0324'
export const CARROT_SEED_ITEM_ID = 'ITEM-0339'
export const GRAPE_SEED_ITEM_ID = 'ITEM-0340'
export const FERNLEAF_SEED_ITEM_ID = 'ITEM-0333'
export const AUGUR_WEED_SEED_ITEM_ID = 'ITEM-0336'
export const MOONBLOSSOM_SEED_ITEM_ID = 'ITEM-0337'
export const TURNIP_SEED_ITEM_ID = 'ITEM-0369'
export const ELDER_BERRY_SEED_ITEM_ID = 'ITEM-0371'
export const HAGROOT_SEED_ITEM_ID = 'ITEM-0373'
export const EMBERBLOSSOM_SEED_ITEM_ID = 'ITEM-0375'
export const SHALLOWS_LOCATION_ID = 'LOC-0043'
export const COMPOST_ITEM_ID = 'ITEM-0377'
export const COMPOST_COLLECT_POOL_ID = 'POOL-0049'
export const COMPOST_COLLECT_ACTION_ID = 'ACN-0199'
export const COMPOST_SEED_COST = 1
export const COMPOST_SAPLING_COST = 5
export const BOTANY_ALL_DIED_TITLE = 'Oh no everything died!'

/** Parent pairs that can return a different seed when both are in the planted pool. */
export const BOTANY_SEED_MUTATIONS: ReadonlyArray<{ parents: readonly string[]; product: string }> =
  [
    { parents: [POTATO_SEED_ITEM_ID, CARROT_SEED_ITEM_ID], product: TURNIP_SEED_ITEM_ID },
    { parents: [GRAPE_SEED_ITEM_ID, POTATO_SEED_ITEM_ID], product: ELDER_BERRY_SEED_ITEM_ID },
    { parents: [FERNLEAF_SEED_ITEM_ID, AUGUR_WEED_SEED_ITEM_ID], product: HAGROOT_SEED_ITEM_ID },
    {
      parents: [AUGUR_WEED_SEED_ITEM_ID, MOONBLOSSOM_SEED_ITEM_ID],
      product: EMBERBLOSSOM_SEED_ITEM_ID,
    },
  ]

/** After the 50% seed-return succeeds, a parent in an active combo is 50% itself
 * and the other 50% is split among those products. Pool-based, not order-based. */
export function rollReturnedBotanySeed(
  plantedSeedIds: readonly string[],
  returningSeedId: string,
  random: () => number,
): string {
  const pool = new Set(plantedSeedIds)
  const products = BOTANY_SEED_MUTATIONS.filter(
    (combo) => combo.parents.includes(returningSeedId) && combo.parents.every((id) => pool.has(id)),
  ).map((combo) => combo.product)
  if (products.length === 0) return returningSeedId
  const roll = random()
  if (roll < 0.5) return returningSeedId
  const share = 0.5 / products.length
  const index = Math.min(products.length - 1, Math.max(0, Math.floor((roll - 0.5) / share)))
  return products[index] ?? returningSeedId
}

/** Strip Seed / Sapling / Spores so skill menus and plant lists show the plant. */
export function botanyPlantDisplayName(name: string): string {
  const stripped = name.replace(/\s+(Seed|Sapling|Spores)$/i, '').trim()
  return stripped.length > 0 ? stripped : name
}

/** Live-plant chance, 0–100. Compost adds +25. Already-growing plots treat missing compost as off. */
export function botanySuccessChancePercent(
  botanyLevel: number,
  requiredLevel: number,
  usedCompost = false,
): number {
  const level = Math.max(0, botanyLevel)
  const required = requiredLevel < 1 ? 1 : requiredLevel
  const chance = 25 + 0.5 * level + 0.5 * Math.max(0, level - required) + (usedCompost ? 25 : 0)
  return Math.min(100, chance)
}

export function compostCostForSpecs(specs: ReadonlyArray<{ isSapling: boolean }>): number {
  return specs.reduce(
    (sum, spec) => sum + (spec.isSapling ? COMPOST_SAPLING_COST : COMPOST_SEED_COST),
    0,
  )
}

export function inventoryCompostCount(save: PlayerSave): number {
  return save.inventory
    .filter((stack) => stack.itemId === COMPOST_ITEM_ID)
    .reduce((sum, stack) => sum + stack.quantity, 0)
}

export function isCompostCollectActivity(activity: {
  'Pool ID'?: string | null
  'Internal Key'?: string | null
  'Location ID'?: string | null
}): boolean {
  return activity['Pool ID'] === COMPOST_COLLECT_POOL_ID
}

export function compostCollectActivityAt(db: GameDatabase, locationId: string) {
  return db.Activities.find(
    (row) => row['Location ID'] === locationId && isCompostCollectActivity(row),
  )
}

export const FISHING_POT_ITEM_ID = 'ITEM-0347'
/** @deprecated Use FISHING_POT_ITEM_ID */
export const FISHING_TRAP_ITEM_ID = FISHING_POT_ITEM_ID
export const FISHING_SKILL_ID = 'SKL-0003'
export const HUNTING_SKILL_ID = 'SKL-0005'
export const POT_BAIT_COUNT = 3
export const POT_CATCH_MIN = 3
export const POT_CATCH_MAX = 6

/** Rod fish → pot catch, ordered by overall fishing level. */
export const POT_BAIT_TO_CATCH: Record<string, string> = {
  'ITEM-0047': 'ITEM-0352', // Perch → Crawfish
  'ITEM-0048': 'ITEM-0353', // Trout → Red Crab
  'ITEM-0049': 'ITEM-0354', // Salmon → Catfish
  'ITEM-0050': 'ITEM-0355', // Tuna → Dungeness
  'ITEM-0051': 'ITEM-0356', // Shark → Eel
  'ITEM-0191': 'ITEM-0357', // Baby Giant Squid → Lobster
}

/** Botany patches: Farm, Courtyard, Gathering Outskirts, The Slopes, Shallows, Temple, Meadow. */
export const BOTANY_PATCH_LOCATIONS = new Set([
  'LOC-0001',
  'LOC-0014',
  'LOC-0031',
  'LOC-0046',
  'LOC-0043',
  'LOC-0036',
  'LOC-0009',
])

export function locationHasCompostCollect(locationId: string): boolean {
  return BOTANY_PATCH_LOCATIONS.has(locationId) && locationId !== SHALLOWS_LOCATION_ID
}

export const FISHING_POT_LOCATIONS = new Set(['LOC-0003', 'LOC-0004'])
/** @deprecated Use FISHING_POT_LOCATIONS */
export const FISHING_TRAP_LOCATIONS = FISHING_POT_LOCATIONS

/** Default trap soak time: 6 hours. */
export const TRAP_DURATION_MS = 6 * 60 * 60 * 1000

/** Ready botany timers stay in place when the bag cannot take the haul. */
export const TIMER_INVENTORY_FULL_HARVEST_REASON =
  'Come back with more room to collect your harvest.'

/** Ready fishing pots stay in place when the bag cannot take the haul. */
export const TIMER_INVENTORY_FULL_CATCH_REASON =
  'Come back with more room to collect your catch.'

export function timerInventoryFullReason(kind: string): string {
  return kind === 'fishing_pot'
    ? TIMER_INVENTORY_FULL_CATCH_REASON
    : TIMER_INVENTORY_FULL_HARVEST_REASON
}

export function isTimerInventoryFullReason(reason: string): boolean {
  return (
    reason === TIMER_INVENTORY_FULL_HARVEST_REASON || reason === TIMER_INVENTORY_FULL_CATCH_REASON
  )
}

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

/** Inventory or bank — used to auto-start / unlock First Planting. */
export function playerHasAnyBotanySeed(db: GameDatabase, save: PlayerSave): boolean {
  const stacks = [...save.inventory, ...(save.bank ?? [])]
  return stacks.some((stack) => stack.quantity > 0 && isBotanySeedItem(db, stack.itemId))
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
      displayName: botanyPlantDisplayName(
        itemById(db, stack.itemId)?.['Display Name'] ?? stack.itemId,
      ),
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
  if (BOTANY_PATCH_LOCATIONS.has(locationId) && botanyPatchUnlocked(save, locationId)) {
    add('botany')
  }
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

/** Ready Botany / fishing pots waiting to be collected. */
export function readyLocationTimerCount(save: PlayerSave, nowMs: number = Date.now()): number {
  return save.locationTimers.filter((timer) => timerIsReady(timer, nowMs)).length
}

export function courtyardBotanyUnlocked(save: PlayerSave): boolean {
  return getQuestProgress(save, GRAND_FEAST_QUEST_ID).status === 'completed'
}

export function farmBotanyUnlocked(save: PlayerSave): boolean {
  const progress = getQuestProgress(save, FIRST_PLANTING_QUEST_ID)
  if (progress.status === 'completed') return true
  const counters = progress.counters ?? {}
  return Object.keys(counters).some(
    (key) => key === `talk:${FENNEL_NPC_ID}` || key.startsWith(`talk:${FENNEL_NPC_ID}:`),
  )
}

export function botanyPatchUnlocked(save: PlayerSave, locationId: string): boolean {
  if (locationId === FARM_LOCATION_ID) return farmBotanyUnlocked(save)
  return true
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
  if (!botanyPatchUnlocked(save, locationId)) {
    return { ok: false, quantity: 0, reason: 'Speak with Fennel before using this plot.' }
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

function countedIngredients(itemIds: string[]): Array<{ itemId: string; quantity: number }> {
  const counts = new Map<string, number>()
  for (const itemId of itemIds) {
    counts.set(itemId, (counts.get(itemId) ?? 0) + 1)
  }
  return [...counts.entries()].map(([itemId, quantity]) => ({ itemId, quantity }))
}

export function canPlantBotanySelection(
  db: GameDatabase,
  save: PlayerSave,
  seedItemIds: string[],
  locationId: string = save.currentLocationId,
): { ok: true; plantedItemIds: string[] } | { ok: false; reason: string } {
  const plantedItemIds = seedItemIds.filter((itemId) => itemId.length > 0)
  if (plantedItemIds.length < 1) {
    return { ok: false, reason: 'Choose a seed or sapling to plant.' }
  }
  if (plantedItemIds.length > 3) {
    return { ok: false, reason: 'A patch holds at most three seeds.' }
  }
  const specs = plantedItemIds.map((itemId) => parseBotanySeedSpec(db, itemId))
  if (specs.some((spec) => !spec)) {
    return { ok: false, reason: 'That item cannot be planted.' }
  }
  const saplingCount = specs.filter((spec) => spec?.isSapling).length
  if (saplingCount > 0 && plantedItemIds.length !== 1) {
    return { ok: false, reason: 'A patch holds one sapling.' }
  }
  const uniqueIds = [...new Set(plantedItemIds)]
  for (const itemId of uniqueIds) {
    const want = plantedItemIds.filter((id) => id === itemId).length
    const gate = canPlantBotanySeed(db, save, itemId, locationId, want)
    if (!gate.ok) return { ok: false, reason: gate.reason }
    if (gate.quantity < want) {
      return { ok: false, reason: 'You do not have that seed.' }
    }
  }
  return { ok: true, plantedItemIds }
}

export function plantBotanySelection(
  db: GameDatabase,
  save: PlayerSave,
  seedItemIds: string[],
  nowMs: number = Date.now(),
  usedCompost = false,
): { ok: true; save: PlayerSave } | { ok: false; reason: string } {
  const locationId = save.currentLocationId
  const gate = canPlantBotanySelection(db, save, seedItemIds, locationId)
  if (!gate.ok) return { ok: false, reason: gate.reason }
  const plantedItemIds = gate.plantedItemIds
  const specs = plantedItemIds.map((itemId) => parseBotanySeedSpec(db, itemId)!)
  if (usedCompost) {
    if (specs.some((spec) => spec.shallowsOnly)) {
      return { ok: false, reason: 'Compost cannot be used on kelp.' }
    }
    const cost = compostCostForSpecs(specs)
    if (inventoryCompostCount(save) < cost) {
      return {
        ok: false,
        reason: cost === 1 ? 'You need 1 compost for this planting.' : `You need ${cost} compost for this planting.`,
      }
    }
  }
  const consumed = [
    ...countedIngredients(plantedItemIds),
    ...(usedCompost ? [{ itemId: COMPOST_ITEM_ID, quantity: compostCostForSpecs(specs) }] : []),
  ]
  const removed = removeIngredients(save, consumed)
  if (!removed) {
    return {
      ok: false,
      reason: usedCompost ? 'You do not have enough compost.' : 'You do not have that seed.',
    }
  }
  const first = specs[0]!
  const timer: LocationTimer = {
    locationId,
    kind: 'botany',
    inputItemId: plantedItemIds[0]!,
    outputItemId: first.outputItemId,
    outputQuantity: plantedItemIds.length,
    skillId: BOTANY_SKILL_ID,
    xpReward: specs.reduce((sum, spec) => sum + spec.xp, 0),
    startedAt: new Date(nowMs).toISOString(),
    durationMs: Math.max(...specs.map((spec) => spec.growSeconds)) * 1000,
    plantedItemIds,
    usedCompost: usedCompost || undefined,
  }
  let next = discoverTimerSpotsForLocation(
    {
      ...removed,
      locationTimers: [
        ...withoutLocationTimerKind(removed.locationTimers, locationId, 'botany'),
        timer,
      ],
    },
    locationId,
  )
  next = applyQuestPlantProgress(db, next, plantedItemIds)
  next = applyQuestAutoStartOnSeed(db, next)
  return { ok: true, save: applyQuestAutoCompleteOnPlant(db, next).save }
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
  return plantBotanySelection(
    db,
    save,
    Array.from({ length: gate.quantity }, () => seedItemId),
    nowMs,
  )
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
  baitItemIds: string[] = [],
): { ok: true; save: PlayerSave } | { ok: false; reason: string } {
  const locationId = save.currentLocationId
  const gate = canPlaceTrap(db, save, trapItemId, locationId, nowMs)
  if (!gate.ok) return gate
  const bait = normalizePotBait(baitItemIds)
  if (bait === null) {
    return { ok: false, reason: 'Add three bait fish, or place the pot with no bait.' }
  }
  const fishingLevel = getSkillProgress(save, FISHING_SKILL_ID).level
  if (bait.length > 0) {
    const invalid = bait.find((itemId) => !isValidPotBait(locationId, fishingLevel, itemId))
    if (invalid) {
      return { ok: false, reason: 'That bait does not match a pot catch here.' }
    }
  }
  const consumed = [{ itemId: trapItemId, quantity: 1 }, ...countItemIds(bait)]
  const removed = removeIngredients(save, consumed)
  if (!removed) {
    return { ok: false, reason: bait.length > 0 ? 'You do not have that bait.' : 'You do not have a fishing pot.' }
  }
  const timer: LocationTimer = {
    locationId,
    kind: gate.kind,
    inputItemId: trapItemId,
    outputItemId: null,
    outputQuantity: 1,
    skillId: FISHING_SKILL_ID,
    xpReward: 150,
    startedAt: new Date(nowMs).toISOString(),
    durationMs: TRAP_DURATION_MS,
    baitItemIds: bait.length > 0 ? bait : undefined,
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
    { itemId: 'ITEM-0352', fishingLevel: 14, xpEach: 450 },
    { itemId: 'ITEM-0354', fishingLevel: 44, xpEach: 1050 },
    { itemId: 'ITEM-0356', fishingLevel: 64, xpEach: 1560 },
  ],
  'LOC-0004': [
    { itemId: 'ITEM-0353', fishingLevel: 35, xpEach: 840 },
    { itemId: 'ITEM-0355', fishingLevel: 55, xpEach: 1350 },
    { itemId: 'ITEM-0357', fishingLevel: 75, xpEach: 1950 },
  ],
}

export function potFishOptionsForLocation(
  locationId: string,
  fishingLevel: number,
): Array<{ itemId: string; fishingLevel: number; xpEach: number }> {
  return (POT_FISH_BY_LOCATION[locationId] ?? []).filter((row) => fishingLevel >= row.fishingLevel)
}

export function potCatchForBait(baitItemId: string): string | null {
  return POT_BAIT_TO_CATCH[baitItemId] ?? null
}

export function isValidPotBait(locationId: string, fishingLevel: number, baitItemId: string): boolean {
  const catchId = potCatchForBait(baitItemId)
  if (!catchId) return false
  return potFishOptionsForLocation(locationId, fishingLevel).some((row) => row.itemId === catchId)
}

export function potBaitOptionsForLocation(
  db: GameDatabase,
  save: PlayerSave,
  locationId: string,
): Array<{ itemId: string; displayName: string; catchItemId: string; owned: number }> {
  const fishingLevel = getSkillProgress(save, FISHING_SKILL_ID).level
  const options: Array<{ itemId: string; displayName: string; catchItemId: string; owned: number }> = []
  for (const [baitId, catchId] of Object.entries(POT_BAIT_TO_CATCH)) {
    if (!isValidPotBait(locationId, fishingLevel, baitId)) continue
    const item = db.Items.find((row) => row['Item ID'] === baitId)
    options.push({
      itemId: baitId,
      displayName: item?.['Display Name'] ?? baitId,
      catchItemId: catchId,
      owned: save.inventory.find((stack) => stack.itemId === baitId)?.quantity ?? 0,
    })
  }
  return options
}

function normalizePotBait(baitItemIds: string[] | undefined): string[] | null {
  const bait = (baitItemIds ?? []).filter((id) => id.length > 0)
  if (bait.length === 0) return []
  if (bait.length !== POT_BAIT_COUNT) return null
  return bait
}

function countItemIds(itemIds: string[]): Array<{ itemId: string; quantity: number }> {
  const counts = new Map<string, number>()
  for (const itemId of itemIds) counts.set(itemId, (counts.get(itemId) ?? 0) + 1)
  return [...counts.entries()].map(([itemId, quantity]) => ({ itemId, quantity }))
}

function mergeLootRows(
  rows: Array<{ itemId: string; quantity: number; xp: number }>,
): Array<{ itemId: string; quantity: number; xp: number }> {
  const merged = new Map<string, { itemId: string; quantity: number; xp: number }>()
  for (const row of rows) {
    const existing = merged.get(row.itemId)
    if (!existing) {
      merged.set(row.itemId, { ...row })
      continue
    }
    existing.quantity += row.quantity
    existing.xp += row.xp
  }
  return [...merged.values()]
}

function rollFishingPotLoot(
  locationId: string,
  fishingLevel: number,
  baitItemIds: string[] | undefined,
  random: () => number,
): Array<{ itemId: string; quantity: number; xp: number }> {
  const unlocked = potFishOptionsForLocation(locationId, fishingLevel)
  const byId = new Map(unlocked.map((row) => [row.itemId, row]))
  const bait = normalizePotBait(baitItemIds) ?? []
  const rolls: Array<{ itemId: string; quantity: number; xp: number }> = []
  if (bait.length === 0) {
    if (unlocked.length === 0) return []
    for (let i = 0; i < POT_BAIT_COUNT; i += 1) {
      const row = unlocked[Math.floor(random() * unlocked.length)]!
      const quantity = rollInclusive(random, POT_CATCH_MIN, POT_CATCH_MAX)
      rolls.push({ itemId: row.itemId, quantity, xp: row.xpEach * quantity })
    }
    return mergeLootRows(rolls)
  }
  for (const baitId of bait) {
    const catchId = potCatchForBait(baitId)
    const row = catchId ? byId.get(catchId) : undefined
    if (!row) continue
    const quantity = rollInclusive(random, POT_CATCH_MIN, POT_CATCH_MAX)
    rolls.push({ itemId: row.itemId, quantity, xp: row.xpEach * quantity })
  }
  return mergeLootRows(rolls)
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
      bonusXp: Array<{ skillId: string; xp: number }>
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
    const plantedIds =
      timer.plantedItemIds && timer.plantedItemIds.length > 0
        ? timer.plantedItemIds
        : Array.from(
            { length: Math.max(1, timer.outputQuantity > 0 ? Math.round(timer.outputQuantity) : 1) },
            () => timer.inputItemId,
          )
    const botanyLevel = getSkillProgress(save, BOTANY_SKILL_ID).level
    const usedCompost = timer.usedCompost === true
    const successfulIds: string[] = []
    const produce = new Map<string, number>()
    const returned = new Map<string, number>()
    let harvestXp = 0
    for (const seedItemId of plantedIds) {
      const spec = parseBotanySeedSpec(db, seedItemId)
      const outputItemId = spec?.outputItemId ?? timer.outputItemId
      if (!outputItemId) return { ok: false, reason: 'Botany timer is missing its crop.' }
      const chance = botanySuccessChancePercent(botanyLevel, spec?.requiresLevel ?? 1, usedCompost)
      if (random() * 100 >= chance) continue
      successfulIds.push(seedItemId)
      produce.set(outputItemId, (produce.get(outputItemId) ?? 0) + rollInclusive(random, 1, 5))
      harvestXp += spec?.xp ?? 0
    }
    for (const seedItemId of successfulIds) {
      if (random() < 0.5) {
        const returnedId = rollReturnedBotanySeed(successfulIds, seedItemId, random)
        returned.set(returnedId, (returned.get(returnedId) ?? 0) + 1)
      }
    }
    xpGained = harvestXp
    for (const [itemId, quantity] of produce) grants.push({ itemId, quantity })
    for (const [itemId, quantity] of returned) grants.push({ itemId, quantity })
  } else if (timer.kind === 'fishing_pot') {
    const fishingLevel = getSkillProgress(save, FISHING_SKILL_ID).level
    const rolled = rollFishingPotLoot(timer.locationId, fishingLevel, timer.baitItemIds, random)
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
    return { ok: false, reason: timerInventoryFullReason(timer.kind) }
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
  const bonusXp: Array<{ skillId: string; xp: number }> = []
  const awards = [{ skillId, xp: xpGained }]
  if (timer.kind === 'fishing_pot' && xpGained > 0) {
    next = applyXp(next, db, HUNTING_SKILL_ID, xpGained).save
    bonusXp.push({ skillId: HUNTING_SKILL_ID, xp: xpGained })
    awards.push({ skillId: HUNTING_SKILL_ID, xp: xpGained })
  }
  next = creditLootTracker(next, 'timer', `${kind}:${locationId}`, loot, 0, nowMs)
  next = creditXpAwards(next, awards, nowMs)
  next = applyQuestAutoStartOnSeed(db, next)

  return { ok: true, save: next, loot, xpGained, skillId, bonusXp }
}
