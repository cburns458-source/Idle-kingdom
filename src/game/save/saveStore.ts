import type { GameDatabase } from '../data/types'
import { migrateSave } from './migrations'
import {
  SAVE_STORAGE_KEY,
  SAVE_VERSION,
  STARTING_BAKED_POTATO_ID,
  STARTING_BAKED_POTATO_QTY,
  STARTING_GOLD,
  STARTING_LOCATION_ID,
  STARTING_MINOR_STRENGTH_POTION_ID,
  STARTING_WOODEN_AXE_ID,
  type EquippedStack,
  type PlayerSave,
} from './types'

export interface SaveStorage {
  getItem(key: string): string | null
  setItem(key: string, value: string): void
  removeItem(key: string): void
}

function nowIso(): string {
  return new Date().toISOString()
}

function configNumber(db: GameDatabase, key: string, fallback: number): number {
  const row = db.Config.find((entry) => entry.Key === key)
  const value = row?.Value
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback
}

export function createNewSave(db: GameDatabase): PlayerSave {
  const maxHp = configNumber(db, 'starting_max_hp', 1000)
  const timestamp = nowIso()

  const skills = db.Skills.filter((skill) => skill['Release Phase'] === 'Launch').map((skill) => ({
    skillId: skill['Skill ID'],
    level: 1,
    xp: 0,
  }))

  const slots: Record<string, EquippedStack | null> = {}
  for (const slot of db.EquipmentSlots) {
    slots[slot['Slot ID']] = null
  }

  return {
    saveVersion: SAVE_VERSION,
    createdAt: timestamp,
    updatedAt: timestamp,
    characterName: null,
    skills,
    inventory: [
      { itemId: STARTING_BAKED_POTATO_ID, quantity: STARTING_BAKED_POTATO_QTY },
      { itemId: STARTING_MINOR_STRENGTH_POTION_ID, quantity: 1 },
      { itemId: STARTING_WOODEN_AXE_ID, quantity: 1 },
    ],
    equipment: { slots },
    gold: STARTING_GOLD,
    quests: [],
    achievements: [],
    statistics: { values: {} },
    unlockedNpcIds: [],
    unlockedLocationIds: [],
    claimedMerchantTipIds: [],
    critterCollections: [],
    activeCritterSpawns: [],
    critterProgressMs: {},
    settings: { soundEnabled: true, showActivityRewards: true, hudShowTotalXp: false },
    currentLocationId: STARTING_LOCATION_ID,
    currentActivityId: null,
    activityStartedAt: null,
    currentActionId: null,
    actionStartedAt: null,
    actionDurationMs: null,
    combatEnemyId: null,
    combatEnemyHp: null,
    combatRoundStartedAt: null,
    activePotionEffect: null,
    deathPauseUntil: null,
    productionRecipeId: null,
    productionQuantityTotal: null,
    productionQuantityRemaining: null,
    activityTransition: null,
    unattendedProgressAt: timestamp,
    currentHp: maxHp,
    maxHp,
  }
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null
}

export function parseSave(raw: unknown): PlayerSave {
  if (!isObject(raw)) {
    throw new Error('Save data must be an object')
  }
  if (typeof raw.saveVersion !== 'number') {
    throw new Error('Save missing saveVersion')
  }
  if (typeof raw.currentLocationId !== 'string') {
    throw new Error('Save missing currentLocationId')
  }
  if (!Array.isArray(raw.skills) || !Array.isArray(raw.inventory)) {
    throw new Error('Save missing skills or inventory arrays')
  }
  if (typeof raw.gold !== 'number') {
    throw new Error('Save missing gold')
  }

  const save = raw as unknown as PlayerSave
  return migrateSave(save)
}

export function writeSave(save: PlayerSave, storage: SaveStorage = localStorage): PlayerSave {
  const next: PlayerSave = {
    ...save,
    updatedAt: nowIso(),
  }
  storage.setItem(SAVE_STORAGE_KEY, JSON.stringify(next))
  return next
}

export function readSave(storage: SaveStorage = localStorage): PlayerSave | null {
  const raw = storage.getItem(SAVE_STORAGE_KEY)
  if (!raw) return null
  try {
    return parseSave(JSON.parse(raw))
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown parse error'
    throw new Error(`Corrupt local save: ${message}`)
  }
}

export interface LoadOrCreateResult {
  save: PlayerSave
  created: boolean
}

export function loadOrCreateSave(
  db: GameDatabase,
  storage: SaveStorage = localStorage,
): LoadOrCreateResult {
  const existing = readSave(storage)
  if (existing) {
    const migrated = writeSave(existing, storage)
    return { save: migrated, created: false }
  }
  const created = createNewSave(db)
  return { save: writeSave(created, storage), created: true }
}

export function clearSave(storage: SaveStorage = localStorage): void {
  storage.removeItem(SAVE_STORAGE_KEY)
}
