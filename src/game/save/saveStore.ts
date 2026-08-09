import type { GameDatabase } from '../data/types'
import { migrateSave } from './migrations'
import {
  SAVE_STORAGE_KEY,
  SAVE_VERSION,
  STARTING_GOLD,
  STARTING_LOCATION_ID,
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

  const slots: Record<string, string | null> = {}
  for (const slot of db.EquipmentSlots) {
    slots[slot['Slot ID']] = null
  }

  return {
    saveVersion: SAVE_VERSION,
    createdAt: timestamp,
    updatedAt: timestamp,
    skills,
    inventory: [],
    equipment: { slots },
    gold: STARTING_GOLD,
    quests: [],
    achievements: [],
    statistics: { values: {} },
    settings: { soundEnabled: true },
    currentLocationId: STARTING_LOCATION_ID,
    currentActivityId: null,
    activityStartedAt: null,
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
