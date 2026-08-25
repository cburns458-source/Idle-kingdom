import type { GameDatabase } from '../../game/data/types'
import { isValidCharacterName, normalizeCharacterName } from '../../game/save/characterName'
import { migrateSave, SAVE_MIGRATIONS } from '../../game/save/migrations'
import { createNewSave, parseSave, touchSave } from '../../game/save/saveStore'
import { ensureStartingHuntingTool } from '../../game/save/startingGear'
import { SAVE_VERSION, type PlayerSave } from '../../game/save/types'
import { scenario, type JsonValue, type ParityScenario } from '../types'
import { contentDatabase } from './contentDatabase'
import { asJson, baseSave, FIXED_TIMESTAMP_MS, gearedSave } from './saveFixtures'

/** A later clock than the fixtures use, so a stamped time is visibly new. */
const NOW_MS = Date.parse('2026-08-12T21:00:00.000Z')

type LegacyJson = Record<string, JsonValue>

/**
 * Fields each migration step introduces, so an older save can be built by
 * removing everything added after its version instead of by hand.
 */
const INTRODUCED_AT: Array<[number, string[]]> = [
  [2, ['currentActionId', 'actionStartedAt', 'actionDurationMs']],
  [3, ['combatEnemyId', 'combatEnemyHp', 'combatRoundStartedAt', 'deathPauseUntil']],
  [6, ['characterName']],
  [7, ['productionRecipeId', 'productionQuantityTotal', 'productionQuantityRemaining']],
  [8, ['unlockedNpcIds']],
  [9, ['unattendedProgressAt']],
  [10, ['activityTransition']],
  [13, ['activePotionEffect']],
  [15, ['unlockedLocationIds', 'claimedMerchantTipIds']],
  [16, ['critterCollections', 'activeCritterSpawns', 'critterProgressMs']],
  [17, ['cosmetics', 'appearance', 'hasSeenWardrobeIntro']],
  [18, ['locationSearchClaims']],
  [19, ['raceId']],
  [21, ['unlockedRecipeIds']],
  [22, ['bountyHourKey', 'bountyProgress', 'bountyClaimedIds']],
  [23, ['bank']],
  [24, ['rankedPvpDayKey', 'rankedPvpFightsToday', 'rankedPvpWins', 'rankedPvpLosses']],
  [25, ['favoriteActivityByLocationId']],
  [29, ['claimedKingswoodsSling']],
  [30, ['playTimeMs']],
  [31, ['combatSkipEnemyAttack']],
  [32, ['combatBossSleepRoundsRemaining', 'bossRespawnUntilByEnemyId']],
]

/**
 * A save as it would have been written by the given version.
 *
 * Built by stripping later fields off a current save and restoring the shapes
 * that version really stored, so the recorded input is something the migration
 * chain could actually be handed.
 */
function legacySave(db: GameDatabase, version: number): LegacyJson {
  const save: LegacyJson = { ...(asJson(baseSave(db)) as LegacyJson), saveVersion: version }
  for (const [introducedAt, fields] of INTRODUCED_AT) {
    if (version >= introducedAt) continue
    for (const field of fields) delete save[field]
  }

  if (version < 11) {
    // Settings predate two of the three flags.
    save.settings = { soundEnabled: false }
  }
  if (version < 4) {
    // Slots held a bare item ID, and food kept its count in the bag.
    save.equipment = {
      slots: {
        'SLOT-0001': 'ITEM-0100',
        'SLOT-0002': null,
        'SLOT-0003': { itemId: 'ITEM-0160', quantity: '2' },
        'SLOT-0008': 42,
        'SLOT-0011': 'ITEM-0058',
      },
    }
    save.inventory = [
      { itemId: 'ITEM-0058', quantity: 7 },
      { itemId: 'ITEM-0025', quantity: 3 },
    ]
  }
  if (version >= 4 && version < 20) {
    // `favorite: false` was written explicitly before it was normalized away.
    save.inventory = [
      { itemId: 'ITEM-0025', quantity: 3, favorite: false },
      { itemId: 'ITEM-0058', quantity: 2, favorite: true },
    ]
    save.equipment = {
      slots: {
        'SLOT-0001': { itemId: 'ITEM-0100', quantity: 1, favorite: false },
        'SLOT-0002': null,
      },
    }
  }
  if (version === 12) {
    save.combatPotionDamageBonusPercent = 15
  }
  if (version >= 16 && version < 17) {
    // A wardrobe that predates the starter outfit and the pet slot.
    save.cosmetics = { unlocked: ['COS-0004'], equipped: { 'CSLOT-0001': 'COS-0004' } }
  }
  if (version >= 4 && version < 21) {
    save.quests = [
      { questId: 'QST-0001', status: 'completed', progress: 10 },
      { questId: 'QST-0002', status: 'active', progress: 2, counters: { 'ENM-0001': 1 } },
    ]
  }
  return save
}

/** Versions worth replaying: the oldest, both settings rewrites, and the newest. */
const LEGACY_VERSIONS = [1, 3, 4, 9, 12, 16, 19, 20, 21, 22, 23, 30, 31, 32, SAVE_VERSION]

/** Names covering trimming, internal runs of whitespace, clipping, and rejection. */
const RAW_NAMES = [
  'Aldric',
  '  Aldric  ',
  'Aldric   the    Bold',
  '\tTabbed\nName\t',
  '',
  '   ',
  'A very long character name that runs past the stored limit',
  'Ünicode Ñame',
]

/** A version 8 save with no timestamp the absence anchor could be taken from. */
function anchorlessLegacySave(): LegacyJson {
  const save = legacySave(contentDatabase(), 8)
  delete save.updatedAt
  return save
}

/** Inputs `parseSave` must reject, one per guard. */
const MALFORMED_SAVES: JsonValue[] = [
  null,
  7,
  'not a save',
  {},
  { saveVersion: SAVE_VERSION },
  { saveVersion: SAVE_VERSION, currentLocationId: 'LOC-0002' },
  { saveVersion: SAVE_VERSION, currentLocationId: 'LOC-0002', createdAt: '', updatedAt: 3 },
  {
    saveVersion: SAVE_VERSION,
    currentLocationId: 'LOC-0002',
    createdAt: '',
    updatedAt: '',
    skills: [],
    inventory: [],
  },
]

function migrationResult(save: LegacyJson): JsonValue {
  try {
    return { ok: true, save: asJson(migrateSave(save as unknown as PlayerSave, NOW_MS)) }
  } catch (error) {
    return { ok: false, error: error instanceof Error ? error.message : String(error) }
  }
}

function parseResult(raw: JsonValue): JsonValue {
  try {
    return { ok: true, save: asJson(parseSave(raw, NOW_MS)) }
  } catch (error) {
    return { ok: false, error: error instanceof Error ? error.message : String(error) }
  }
}

/** Saves with the hunting tool owned, equipped, or missing entirely. */
function startingGearSaves(db: GameDatabase): Record<string, PlayerSave> {
  const base = baseSave(db)
  return {
    'empty-hands': base,
    'tool-slot-taken': {
      ...base,
      equipment: {
        slots: { ...base.equipment.slots, 'SLOT-0001': { itemId: 'ITEM-0100', quantity: 1 } },
      },
    },
    'owned-in-bag': { ...base, inventory: [{ itemId: 'ITEM-0108', quantity: 2 }] },
    'owned-and-slot-taken': {
      ...base,
      inventory: [{ itemId: 'ITEM-0108', quantity: 1 }],
      equipment: {
        slots: { ...base.equipment.slots, 'SLOT-0001': { itemId: 'ITEM-0100', quantity: 1 } },
      },
    },
    geared: gearedSave(db),
  }
}

export const saveScenarios: ParityScenario[] = [
  scenario('save/new', 'created', { source: 'content', nowMs: FIXED_TIMESTAMP_MS }, () =>
    asJson(createNewSave(contentDatabase(), FIXED_TIMESTAMP_MS)),
  ),

  scenario(
    'save/migrations',
    'registry',
    { source: 'content' },
    () =>
      ({
        currentVersion: SAVE_VERSION,
        steps: SAVE_MIGRATIONS.map((entry) => ({
          fromVersion: entry.fromVersion,
          toVersion: entry.toVersion,
        })),
      }) as unknown as JsonValue,
  ),

  ...LEGACY_VERSIONS.map((version) =>
    scenario(
      'save/migrations',
      `from-v${version}`,
      {
        source: 'content',
        nowMs: NOW_MS,
        legacy: legacySave(contentDatabase(), version) as JsonValue,
      },
      () => migrationResult(legacySave(contentDatabase(), version)),
    ),
  ),

  scenario(
    'save/migrations',
    'unsupported',
    {
      source: 'content',
      nowMs: NOW_MS,
      cases: [
        { name: 'from-the-future', legacy: legacySave(contentDatabase(), SAVE_VERSION + 1) },
        { name: 'no-step-registered', legacy: legacySave(contentDatabase(), 0) },
      ] as unknown as JsonValue,
    },
    () =>
      ({
        'from-the-future': migrationResult(legacySave(contentDatabase(), SAVE_VERSION + 1)),
        'no-step-registered': migrationResult(legacySave(contentDatabase(), 0)),
      }) as unknown as JsonValue,
  ),

  scenario(
    'save/migrations',
    'missing-timestamps',
    {
      source: 'content',
      nowMs: NOW_MS,
      withUpdatedAt: legacySave(contentDatabase(), 8) as JsonValue,
      // Nothing to anchor absence catch-up to, so the clock stands in.
      anchorless: anchorlessLegacySave() as JsonValue,
    },
    () =>
      ({
        withUpdatedAt: migrationResult(legacySave(contentDatabase(), 8)),
        anchorless: migrationResult(anchorlessLegacySave()),
      }) as unknown as JsonValue,
  ),

  scenario(
    'save/parse',
    'guards',
    { source: 'content', nowMs: NOW_MS, cases: MALFORMED_SAVES },
    () => MALFORMED_SAVES.map((entry) => parseResult(entry)) as unknown as JsonValue,
  ),

  scenario(
    'save/parse',
    'round-trip',
    {
      source: 'content',
      nowMs: NOW_MS,
      legacy: legacySave(contentDatabase(), 4) as JsonValue,
    },
    () => parseResult(legacySave(contentDatabase(), 4) as JsonValue),
  ),

  scenario(
    'save/touch',
    'stamps-updated-at',
    { source: 'content', save: asJson(baseSave(contentDatabase())), nowMs: NOW_MS },
    () => asJson(touchSave(baseSave(contentDatabase()), NOW_MS)),
  ),

  scenario('save/character-name', 'normalize', { names: RAW_NAMES }, () =>
    RAW_NAMES.map((raw) => ({
      raw,
      normalized: normalizeCharacterName(raw),
      valid: isValidCharacterName(raw),
    })) as unknown as JsonValue,
  ),

  scenario(
    'save/starting-gear',
    'ensure-hunting-tool',
    {
      source: 'content',
      saves: Object.fromEntries(
        Object.entries(startingGearSaves(contentDatabase())).map(([name, save]) => [
          name,
          asJson(save),
        ]),
      ),
    },
    () =>
      Object.fromEntries(
        Object.entries(startingGearSaves(contentDatabase())).map(([name, save]) => [
          name,
          asJson(ensureStartingHuntingTool(save)),
        ]),
      ) as unknown as JsonValue,
  ),
]
