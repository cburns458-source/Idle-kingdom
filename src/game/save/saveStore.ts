import type { GameDatabase } from '../data/types'
import { migrateSave } from './migrations'
import {
  DEFAULT_BEARD_ID,
  DEFAULT_EXPRESSION_ID,
  DEFAULT_GENDER_PRESENTATION_ID,
  DEFAULT_HAIRSTYLE_ID,
  DEFAULT_HAIR_COLOR_ID,
  DEFAULT_SKIN_TONE_ID,
  OUTFIT_COSMETIC_SLOT_ID,
  PET_COSMETIC_SLOT_ID,
  SAVE_STORAGE_KEY,
  SAVE_VERSION,
  STARTER_OUTFIT_COSMETIC_ID,
  STARTING_GOLD,
  STARTING_LOCATION_ID,
  type EquippedStack,
  type PlayerSave,
} from './types'

export interface SaveStorage {
  getItem(key: string): string | null
  setItem(key: string, value: string): void
  removeItem(key: string): void
}

function configNumber(db: GameDatabase, key: string, fallback: number): number {
  const row = db.Config.find((entry) => entry.Key === key)
  const value = row?.Value
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback
}

export function createNewSave(db: GameDatabase, nowMs: number = Date.now()): PlayerSave {
  const maxHp = configNumber(db, 'starting_max_hp', 1000)
  const timestamp = new Date(nowMs).toISOString()

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
    raceId: null,
    skills,
    // Race-specific starter kits are granted when the player picks a race.
    inventory: [],
    bank: [],
    favoriteActivityByLocationId: {},
    equipment: { slots },
    gold: STARTING_GOLD,
    quests: [],
    achievements: [],
    statistics: { values: {} },
    unlockedNpcIds: [],
    unlockedRecipeIds: [],
    unlockedLocationIds: [],
    bountyHourKey: null,
    bountyProgress: {},
    bountyClaimedIds: [],
    rankedPvpDayKey: null,
    rankedPvpFightsToday: 0,
    rankedPvpWins: 0,
    rankedPvpLosses: 0,
    claimedMerchantTipIds: [],
    critterCollections: [],
    activeCritterSpawns: [],
    critterProgressMs: {},
    locationSearchClaims: {},
    cosmetics: {
      unlocked: [STARTER_OUTFIT_COSMETIC_ID],
      equipped: {
        [OUTFIT_COSMETIC_SLOT_ID]: STARTER_OUTFIT_COSMETIC_ID,
        [PET_COSMETIC_SLOT_ID]: null,
      },
    },
    appearance: {
      skinTone: DEFAULT_SKIN_TONE_ID,
      hairstyle: DEFAULT_HAIRSTYLE_ID,
      hairColor: DEFAULT_HAIR_COLOR_ID,
      expression: DEFAULT_EXPRESSION_ID,
      beard: DEFAULT_BEARD_ID,
      genderPresentation: DEFAULT_GENDER_PRESENTATION_ID,
    },
    hasSeenWardrobeIntro: false,
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

export function parseSave(raw: unknown, nowMs: number = Date.now()): PlayerSave {
  if (!isObject(raw)) {
    throw new Error('Save data must be an object')
  }
  if (typeof raw.saveVersion !== 'number') {
    throw new Error('Save missing saveVersion')
  }
  if (typeof raw.currentLocationId !== 'string') {
    throw new Error('Save missing currentLocationId')
  }
  // Every save ever written stamped both, and the Dart client's model requires
  // them, so a save without them is corrupt rather than merely old.
  if (typeof raw.createdAt !== 'string' || typeof raw.updatedAt !== 'string') {
    throw new Error('Save missing timestamps')
  }
  if (!Array.isArray(raw.skills) || !Array.isArray(raw.inventory)) {
    throw new Error('Save missing skills or inventory arrays')
  }
  if (typeof raw.gold !== 'number') {
    throw new Error('Save missing gold')
  }

  const save = raw as unknown as PlayerSave
  return migrateSave(save, nowMs)
}

/** The pure half of a save write: stamp the touch time. */
export function touchSave(save: PlayerSave, nowMs: number = Date.now()): PlayerSave {
  return {
    ...save,
    updatedAt: new Date(nowMs).toISOString(),
  }
}

export function writeSave(save: PlayerSave, storage: SaveStorage = localStorage): PlayerSave {
  const next = touchSave(save)
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
