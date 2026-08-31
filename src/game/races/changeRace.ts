import type { GameDatabase } from '../data/types'
import { inventoryCount } from '../production/recipes'
import { removeIngredients } from '../production/inventory'
import {
  miniquestCanRepeat,
  recordMiniquestCompletion,
  formatDurationRemaining,
  miniquestRepeatReadyAt,
  meetsTotalLevelRequirement,
} from '../quests/miniquests'
import { getQuest } from '../quests/quests'
import type { PlayerSave } from '../save/types'
import { totalLevel } from '../skills/totals'
import { assignRace } from './assignRace'
import { raceBonusSummaryLines, raceById, raceDisplayName, races } from './races'

export const VESPER_ID = 'NPC-0016'
export const RACE_CHANGE_MINIQUEST_ID = 'QST-0009'
export const RACE_CHANGE_TOTAL_LEVEL = 500
export const RACE_CHANGE_COOLDOWN_MS = 7 * 24 * 60 * 60 * 1000

export interface RaceChangeItemCost {
  itemId: string
  quantity: number
}

export interface RaceChangeCost {
  gold: number
  items: RaceChangeItemCost[]
}

/** Mid-level (30–55) costs. No gems or ruby. Human stays tuna and maple. */
export const RACE_CHANGE_COSTS: Record<string, RaceChangeCost> = {
  // Human — fishing 40 + woodcutting 50
  'RACE-0001': {
    gold: 0,
    items: [
      { itemId: 'ITEM-0050', quantity: 40 },
      { itemId: 'ITEM-0018', quantity: 40 },
    ],
  },
  // Wood Elf — hunt elk 35 + mountain goat 50
  'RACE-0002': {
    gold: 0,
    items: [
      { itemId: 'ITEM-0041', quantity: 20 },
      { itemId: 'ITEM-0196', quantity: 20 },
    ],
  },
  // High Elf — crafting 35, alchemy 40, cooking 40
  'RACE-0003': {
    gold: 0,
    items: [
      { itemId: 'ITEM-0099', quantity: 15 },
      { itemId: 'ITEM-0071', quantity: 10 },
      { itemId: 'ITEM-0062', quantity: 15 },
    ],
  },
  // Orc — hunting 35 + leather
  'RACE-0004': {
    gold: 0,
    items: [
      { itemId: 'ITEM-0045', quantity: 20 },
      { itemId: 'ITEM-0041', quantity: 15 },
    ],
  },
  // Goblin — gold + steel 35
  'RACE-0005': {
    gold: 5000,
    items: [{ itemId: 'ITEM-0077', quantity: 20 }],
  },
  // Dwarf — iron, coal 35 (20), silver 45
  'RACE-0006': {
    gold: 0,
    items: [
      { itemId: 'ITEM-0005', quantity: 60 },
      { itemId: 'ITEM-0006', quantity: 20 },
      { itemId: 'ITEM-0007', quantity: 20 },
    ],
  },
  // Halfling — wild berries 30 + augur weed 50 (not grapes)
  'RACE-0007': {
    gold: 0,
    items: [
      { itemId: 'ITEM-0028', quantity: 40 },
      { itemId: 'ITEM-0033', quantity: 20 },
    ],
  },
}

export function raceChangeCostFor(raceId: string): RaceChangeCost | null {
  return RACE_CHANGE_COSTS[raceId] ?? null
}

export function raceChangeUnlocked(save: PlayerSave): boolean {
  return totalLevel(save) >= RACE_CHANGE_TOTAL_LEVEL
}

export function raceChangeQuest(db: GameDatabase) {
  return getQuest(db, RACE_CHANGE_MINIQUEST_ID)
}

export function raceChangeReady(db: GameDatabase, save: PlayerSave, nowMs: number): boolean {
  if (!raceChangeUnlocked(save)) return false
  const quest = raceChangeQuest(db)
  if (!quest) return false
  if (!meetsTotalLevelRequirement(save, quest.Notes)) return false
  return miniquestCanRepeat(save, quest, nowMs)
}

export function raceChangeCooldownLabel(
  db: GameDatabase,
  save: PlayerSave,
  nowMs: number,
): string | null {
  const quest = raceChangeQuest(db)
  if (!quest) return null
  const readyAt = miniquestRepeatReadyAt(save, quest)
  if (readyAt == null || nowMs >= readyAt) return null
  return `Come back in ${formatDurationRemaining(readyAt - nowMs)}.`
}

export interface RaceChangeCostLine {
  itemId: string | null
  name: string
  owned: number
  required: number
}

export interface RaceChangeOption {
  raceId: string
  name: string
  summary: string
  current: boolean
  goldRequired: number
  lines: RaceChangeCostLine[]
  canAfford: boolean
}

export interface RaceChangeOffer {
  questId: string
  ready: boolean
  cooldownEndsAt: string | null
  cooldownLabel: string | null
  warning: string
  prompt: string
  currentRaceId: string | null
  currentRaceName: string | null
  options: RaceChangeOption[]
}

const RACE_CHANGE_WARNING =
  'The change lasts. Old gifts fade and new ones take their place. I can do this once a week — the weave needs time to settle.'

const RACE_CHANGE_PROMPT =
  "You've grown into yourself, haven't you? I can change the blood you wear, if you still want a different kind of life. Bring what I ask."

function itemName(db: GameDatabase, itemId: string): string {
  return db.Items.find((row) => row['Item ID'] === itemId)?.['Display Name'] ?? itemId
}

function costLines(db: GameDatabase, save: PlayerSave, cost: RaceChangeCost): RaceChangeCostLine[] {
  const lines: RaceChangeCostLine[] = []
  if (cost.gold > 0) {
    lines.push({
      itemId: null,
      name: 'Gold',
      owned: save.gold,
      required: cost.gold,
    })
  }
  for (const item of cost.items) {
    lines.push({
      itemId: item.itemId,
      name: itemName(db, item.itemId),
      owned: inventoryCount(save, item.itemId),
      required: item.quantity,
    })
  }
  return lines
}

function canAfford(save: PlayerSave, cost: RaceChangeCost): boolean {
  if (save.gold < cost.gold) return false
  return cost.items.every((item) => inventoryCount(save, item.itemId) >= item.quantity)
}

export function raceChangeOffer(
  db: GameDatabase,
  save: PlayerSave,
  nowMs: number = Date.now(),
): RaceChangeOffer {
  const quest = raceChangeQuest(db)
  const ready = raceChangeReady(db, save, nowMs)
  const readyAt = quest ? miniquestRepeatReadyAt(save, quest) : null
  const options = races(db).map((race) => {
    const raceId = race['Race ID']
    const cost = raceChangeCostFor(raceId) ?? { gold: 0, items: [] }
    const lines = costLines(db, save, cost)
    return {
      raceId,
      name: race['Display Name'],
      summary: raceBonusSummaryLines(db, raceId).join(' · ') || (race.Description ?? ''),
      current: save.raceId === raceId,
      goldRequired: cost.gold,
      lines,
      canAfford: canAfford(save, cost),
    }
  })
  return {
    questId: RACE_CHANGE_MINIQUEST_ID,
    ready,
    cooldownEndsAt: readyAt != null && nowMs < readyAt ? new Date(readyAt).toISOString() : null,
    cooldownLabel: raceChangeCooldownLabel(db, save, nowMs),
    warning: RACE_CHANGE_WARNING,
    prompt: (db.Quests.find((row) => row['Quest ID'] === RACE_CHANGE_MINIQUEST_ID)?.Pitch as string | undefined) ||
      RACE_CHANGE_PROMPT,
    currentRaceId: save.raceId,
    currentRaceName: raceDisplayName(db, save.raceId),
    options,
  }
}

export function changeRaceAtNpc(
  db: GameDatabase,
  save: PlayerSave,
  raceId: string,
  nowMs: number = Date.now(),
): { ok: true; save: PlayerSave; message: string } | { ok: false; reason: string } {
  const npc = db.NPCs.find((row) => row['NPC ID'] === VESPER_ID)
  if (!npc) return { ok: false, reason: 'Vesper is not here.' }
  if (save.currentLocationId !== npc['Location ID']) {
    return { ok: false, reason: 'Speak with Vesper in the Main Hall.' }
  }
  if (save.raceId == null) {
    return { ok: false, reason: 'Choose a race first.' }
  }
  if (save.raceId === raceId) {
    return { ok: false, reason: 'You already wear that blood.' }
  }
  if (!raceById(db, raceId)) return { ok: false, reason: 'Unknown race.' }
  if (!raceChangeUnlocked(save)) {
    return { ok: false, reason: 'Vesper has nothing to say to you yet.' }
  }
  const quest = raceChangeQuest(db)
  if (!quest) return { ok: false, reason: 'This work is not ready.' }
  if (!miniquestCanRepeat(save, quest, nowMs)) {
    return { ok: false, reason: raceChangeCooldownLabel(db, save, nowMs) ?? 'The last change is still settling.' }
  }

  const cost = raceChangeCostFor(raceId)
  if (!cost) return { ok: false, reason: 'Vesper will not weave that shape.' }
  if (save.gold < cost.gold) {
    return { ok: false, reason: `Need ${cost.gold.toLocaleString()} gold.` }
  }
  const spentItems =
    cost.items.length === 0
      ? save
      : removeIngredients(save, cost.items)
  if (!spentItems) {
    return { ok: false, reason: 'You do not have what the weave asks.' }
  }
  const spentGold = { ...spentItems, gold: spentItems.gold - cost.gold }
  const assigned = assignRace(db, spentGold, raceId)
  if (!assigned.ok) return assigned

  const next = recordMiniquestCompletion(assigned.save, RACE_CHANGE_MINIQUEST_ID, nowMs)
  const name = raceDisplayName(db, raceId) ?? raceId
  return {
    ok: true,
    save: next,
    message: `There. Walk as ${name} now. The world will treat you accordingly.`,
  }
}
