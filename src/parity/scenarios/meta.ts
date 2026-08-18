import { hasEveryCritter, syncProgressionMeta } from '../../game/achievements/progress'
import { applyBountyReward, prepareBountyTurnIn } from '../../game/bounties/complete'
import { hourlyBountyBoard } from '../../game/bounties/rotation'
import type { BountyDefinition } from '../../game/bounties/types'
import {
  APPEARANCE_CATEGORIES,
  appearanceCategoryLabel,
  appearanceOptionById,
  appearanceOptions,
  defaultAppearance,
  isValidAppearanceOption,
  setAppearanceOption,
  withAppearanceOption,
} from '../../game/cosmetics/appearance'
import {
  appearanceSliders,
  cosmeticUnlockNotice,
  wardrobeSlotTabs,
  wardrobeSlotView,
} from '../../game/cosmetics/wardrobe'
import {
  activeSpawnAtLocation,
  applyActivityTimeTowardCritters,
  collectCritter,
  collectionCount,
  CRITTER_DEFS,
  CRITTER_HOUR_MS,
  critterForLocation,
  getCritter,
  spawnCritterAtLocation,
} from '../../game/critters/critters'
import { achievementLog, critterLog, logCompletion, questLog, recipeLog } from '../../game/log/log'
import { mulberry32 } from '../../game/rng/mulberry32'
import { displayNameForSave, nameWithTitle, titleForSave } from '../../game/save/playerTitle'
import type { PlayerSave } from '../../game/save/types'
import { scenario, type JsonValue, type ParityScenario } from '../types'
import { contentDatabase } from './contentDatabase'
import {
  asJson,
  baseSave,
  fullBagSave,
  gearedSave,
  questSave,
  richSave,
} from './saveFixtures'

const NOW_MS = Date.parse('2026-08-12T21:00:00.000Z')

type SaveKind =
  | 'base'
  | 'bare'
  | 'stale-look'
  | 'rich'
  | 'geared'
  | 'collector'
  | 'completionist'
  | 'deliverer'
  | 'quest-runner'
  | 'full-bag'

/** Critters already banked and one waiting at the Farm. */
function collectorSave(): PlayerSave {
  const base = baseSave(contentDatabase())
  return {
    ...base,
    characterName: 'Collector',
    currentLocationId: 'LOC-0001',
    critterCollections: [
      { critterId: 'CRT-0001', count: 3 },
      { critterId: 'CRT-0002', count: 1 },
    ],
    activeCritterSpawns: [
      { locationId: 'LOC-0001', critterId: 'CRT-0001', appearedAt: '2026-08-12T20:00:00.000Z' },
      { locationId: 'LOC-0004', critterId: 'CRT-9999', appearedAt: '2026-08-12T20:00:00.000Z' },
    ],
    critterProgressMs: { 'LOC-0001': CRITTER_HOUR_MS - 1_000, 'LOC-0004': 0 },
  }
}

/** One of every critter banked, which is what Critter Collector asks for. */
function completionistSave(): PlayerSave {
  return {
    ...baseSave(contentDatabase()),
    characterName: 'Completionist',
    critterCollections: CRITTER_DEFS.map((critter) => ({ critterId: critter.id, count: 1 })),
  }
}

/** Carrying every gather-deliver target on the current board, twice over. */
function delivererSave(): PlayerSave {
  const base = baseSave(contentDatabase())
  const board = hourlyBountyBoard(NOW_MS)
  const inventory = board.bounties
    .filter((bounty) => bounty.kind === 'gather_deliver')
    .map((bounty) => ({ itemId: bounty.targetId, quantity: bounty.amount * 2 }))
  return {
    ...base,
    characterName: 'Courier',
    bountyHourKey: board.hourKey,
    bountyProgress: Object.fromEntries(
      board.bounties.map((bounty) => [bounty.id, bounty.amount] as const),
    ),
    inventory: [
      ...inventory,
      // An enchanted copy of the first delivery target, which cannot be handed in.
      ...(inventory[0] ? [{ ...inventory[0], quantity: 1, enchantmentId: 'ENCH-0001' }] : []),
    ],
  }
}

function saveFor(kind: SaveKind): PlayerSave {
  const db = contentDatabase()
  if (kind === 'base') return baseSave(db)
  // Nothing unlocked and nothing worn, which is what the wardrobe's empty state reads.
  if (kind === 'bare') return { ...baseSave(db), cosmetics: { unlocked: [], equipped: {} } }
  // Appearance ids the tables no longer list, so the sliders must fall back.
  if (kind === 'stale-look') {
    const base = baseSave(db)
    return {
      ...base,
      appearance: { ...base.appearance, hairstyle: 'APR-9999', genderPresentation: 'APR-8888' },
    }
  }
  if (kind === 'rich') return richSave(db)
  if (kind === 'geared') return gearedSave(db)
  if (kind === 'collector') return collectorSave()
  if (kind === 'completionist') return completionistSave()
  if (kind === 'deliverer') return delivererSave()
  // One quest done and one running with part of its delivery, for the log's bars.
  if (kind === 'quest-runner') return questSave(db)
  return fullBagSave(db, ['ITEM-0100'])
}

function withSave(kind: SaveKind, extra: Record<string, JsonValue> = {}): JsonValue {
  return { source: 'content', save: asJson(saveFor(kind)), nowMs: NOW_MS, ...extra }
}

const CRITTER_LOCATIONS = ['LOC-0001', 'LOC-0004', 'LOC-0011', 'LOC-0018', 'LOC-0002']
const CRITTER_IDS = ['CRT-0001', 'CRT-0004', 'CRT-9999']
const APPEARANCE_OPTIONS = ['APR-0001', 'APR-0004', 'APR-0007', 'APR-0017', 'APR-9999']
const WARDROBE_SLOTS = ['CSLOT-0001', 'CSLOT-0002', 'CSLOT-0003', 'CSLOT-9999']
const WARDROBE_COSMETICS = ['COS-0001', 'COS-9999']

/** Elapsed spans in hours, so the roll count and the kept remainder both vary. */
const CRITTER_SPANS = [0, -1, 1_000, CRITTER_HOUR_MS, CRITTER_HOUR_MS * 5 + 500]

export const metaScenarios: ParityScenario[] = [
  scenario('critters/catalog', 'defs', { source: 'content', locations: CRITTER_LOCATIONS }, () => ({
    defs: CRITTER_DEFS as unknown as JsonValue,
    byLocation: CRITTER_LOCATIONS.map((locationId) => ({
      locationId,
      critterId: critterForLocation(locationId)?.id ?? null,
    })),
    byId: CRITTER_IDS.map((critterId) => ({
      critterId,
      internalKey: getCritter(critterId)?.internalKey ?? null,
    })),
  }) as unknown as JsonValue),

  ...(['base', 'collector'] as const).map((kind) =>
    scenario(
      'critters/collection',
      kind,
      withSave(kind, { locations: CRITTER_LOCATIONS, critterIds: CRITTER_IDS }),
      () => {
        const save = saveFor(kind)
        return {
          counts: CRITTER_IDS.map((critterId) => collectionCount(save, critterId)),
          spawns: CRITTER_LOCATIONS.map((locationId) => ({
            locationId,
            spawn: activeSpawnAtLocation(save, locationId),
          })),
          collected: CRITTER_LOCATIONS.map((locationId) => {
            const result = collectCritter(save, locationId)
            return {
              locationId,
              ...(result.ok
                ? {
                    ok: true,
                    save: asJson(result.save),
                    critterId: result.critter.id,
                    count: result.count,
                    message: result.message,
                  }
                : result),
            }
          }),
          forced: CRITTER_LOCATIONS.map((locationId) => {
            const result = spawnCritterAtLocation(save, locationId, NOW_MS)
            return {
              locationId,
              ...(result.ok
                ? { ok: true, save: asJson(result.save), critterId: result.critter.id }
                : result),
            }
          }),
        } as unknown as JsonValue
      },
    ),
  ),

  ...([
    { name: 'no-spawn', save: 'base' as const, seed: 7, location: 'LOC-0001' },
    { name: 'spawns', save: 'base' as const, seed: 3, location: 'LOC-0001' },
    { name: 'already-waiting', save: 'collector' as const, seed: 3, location: 'LOC-0001' },
    { name: 'no-habitat', save: 'base' as const, seed: 3, location: 'LOC-0002' },
  ]).map((entry) =>
    scenario(
      'critters/hours',
      entry.name,
      withSave(entry.save, { seed: entry.seed, location: entry.location, spans: CRITTER_SPANS }),
      () => ({
        bySpan: CRITTER_SPANS.map((elapsedMs) => {
          const result = applyActivityTimeTowardCritters(
            saveFor(entry.save),
            entry.location,
            elapsedMs,
            NOW_MS,
            mulberry32(entry.seed),
          )
          return {
            elapsedMs,
            save: asJson(result.save),
            spawnedId: result.spawned?.id ?? null,
            hoursRolled: result.hoursRolled,
          }
        }),
      }) as unknown as JsonValue,
    ),
  ),

  scenario(
    'critters/hours',
    'guaranteed-spawn',
    withSave('base', { location: 'LOC-0001', spans: CRITTER_SPANS }),
    () => ({
      // A generator pinned to 0 always rolls under the 1/200 spawn chance.
      bySpan: CRITTER_SPANS.map((elapsedMs) => {
        const result = applyActivityTimeTowardCritters(
          saveFor('base'),
          'LOC-0001',
          elapsedMs,
          NOW_MS,
          () => 0,
        )
        return {
          elapsedMs,
          save: asJson(result.save),
          spawnedId: result.spawned?.id ?? null,
          hoursRolled: result.hoursRolled,
        }
      }),
    }) as unknown as JsonValue,
  ),

  scenario(
    'cosmetics/appearance',
    'options',
    { source: 'content', categories: APPEARANCE_CATEGORIES as unknown as JsonValue },
    () => {
      const db = contentDatabase()
      return {
        defaults: defaultAppearance(db) as unknown as JsonValue,
        byCategory: APPEARANCE_CATEGORIES.map((category) => ({
          category,
          label: appearanceCategoryLabel(category),
          options: appearanceOptions(db, category).map((row) => row['Appearance Option ID']),
          valid: APPEARANCE_OPTIONS.map((optionId) =>
            isValidAppearanceOption(db, category, optionId),
          ),
        })),
        lookups: APPEARANCE_OPTIONS.map((optionId) => ({
          optionId,
          category: appearanceOptionById(db, optionId)?.Category ?? null,
        })),
      } as unknown as JsonValue
    },
  ),

  scenario(
    'cosmetics/appearance',
    'set-option',
    withSave('base', { options: APPEARANCE_OPTIONS }),
    () => {
      const db = contentDatabase()
      const save = saveFor('base')
      return {
        results: APPEARANCE_CATEGORIES.flatMap((category) =>
          APPEARANCE_OPTIONS.map((optionId) => {
            const next = setAppearanceOption(db, save, category, optionId)
            return {
              category,
              optionId,
              appearance: next ? (next.appearance as unknown as JsonValue) : null,
              // The unvalidated setter creation uses, which takes anything.
              direct: withAppearanceOption(save.appearance, category, optionId),
            }
          }),
        ),
      } as unknown as JsonValue
    },
  ),

  ...(['base', 'bare', 'stale-look'] as const).map((kind) =>
    scenario('cosmetics/wardrobe-view', kind, withSave(kind, { slotIds: WARDROBE_SLOTS }), () => {
      const db = contentDatabase()
      const save = saveFor(kind)
      return {
        tabs: wardrobeSlotTabs(db),
        slots: WARDROBE_SLOTS.map((slotId) => wardrobeSlotView(db, save, slotId)),
        sliders: appearanceSliders(db, save.appearance),
        notices: WARDROBE_COSMETICS.flatMap((cosmeticId) =>
          [true, false].map((isFirstEver) => cosmeticUnlockNotice(db, cosmeticId, isFirstEver)),
        ),
      } as unknown as JsonValue
    }),
  ),

  ...(['base', 'rich', 'collector', 'completionist', 'quest-runner'] as const).map((kind) =>
    scenario('log/view', kind, withSave(kind), () => {
      const db = contentDatabase()
      const save = saveFor(kind)
      return {
        achievements: achievementLog(db, save),
        quests: questLog(db, save),
        recipes: recipeLog(db, save),
        critters: critterLog(save),
        completion: logCompletion(db, save) as unknown as JsonValue,
      } as unknown as JsonValue
    }),
  ),

  ...(['base', 'rich', 'geared', 'collector', 'completionist'] as const).map((kind) =>
    scenario('achievements/sync', kind, withSave(kind), () => {
      const db = contentDatabase()
      const once = syncProgressionMeta(db, saveFor(kind), NOW_MS)
      const twice = syncProgressionMeta(db, once, NOW_MS + 60_000)
      return {
        once: asJson(once),
        // Re-running keeps the first unlock timestamps, so it must be idempotent.
        twice: asJson(twice),
        collectsEverything: hasEveryCritter(saveFor(kind)),
      } as unknown as JsonValue
    }),
  ),

  scenario('achievements/revoke', 'new-critter-arrives', withSave('completionist'), () => {
    const db = contentDatabase()
    // A save that held the title, then the world grew a critter it cannot have.
    const held = syncProgressionMeta(db, completionistSave(), NOW_MS)
    const widened: PlayerSave = {
      ...held,
      critterCollections: held.critterCollections.slice(1),
    }
    return {
      held: held.achievements as unknown as JsonValue,
      afterNewCritter: syncProgressionMeta(db, widened, NOW_MS + 60_000)
        .achievements as unknown as JsonValue,
      // Catching up gets it back, so losing it is never permanent.
      regained: syncProgressionMeta(db, completionistSave(), NOW_MS + 120_000)
        .achievements as unknown as JsonValue,
    } as unknown as JsonValue
  }),

  ...(['base', 'rich', 'completionist'] as const).map((kind) =>
    scenario('save/title', kind, withSave(kind), () => {
      const save = saveFor(kind)
      const died: PlayerSave = { ...save, hasEverDied: true }
      const nameless: PlayerSave = { ...save, characterName: null }
      return {
        living: titleForSave(save) as unknown as JsonValue,
        died: titleForSave(died) as unknown as JsonValue,
        displayLiving: displayNameForSave(save, 'Adventurer'),
        displayDied: displayNameForSave(died, 'Adventurer'),
        displayNameless: displayNameForSave(nameless, 'Adventurer'),
        prefixed: nameWithTitle('Rowan', { text: 'Sir', placement: 'prefix' }),
        untitled: nameWithTitle('Rowan', null),
      } as unknown as JsonValue
    }),
  ),

  ...(['base', 'deliverer'] as const).map((kind) =>
    scenario('bounties/turn-in', kind, withSave(kind), () => {
      const board = hourlyBountyBoard(NOW_MS)
      return {
        hourKey: board.hourKey,
        byBounty: board.bounties.map((bounty: BountyDefinition) => {
          const prepared = prepareBountyTurnIn(saveFor(kind), bounty, NOW_MS)
          return {
            bountyId: bounty.id,
            prepared: prepared.ok ? { ok: true, save: asJson(prepared.save) } : prepared,
            rewardFirst: prepared.ok
              ? (applyBountyReward(prepared.save, bounty, true) as unknown as JsonValue)
              : null,
            rewardLater: prepared.ok
              ? (applyBountyReward(prepared.save, bounty, false) as unknown as JsonValue)
              : null,
          }
        }),
      } as unknown as JsonValue
    }),
  ),

  scenario('bounties/turn-in', 'rotated-board', withSave('deliverer'), () => {
    const board = hourlyBountyBoard(NOW_MS)
    const bounty = board.bounties[0]!
    const stale: PlayerSave = { ...saveFor('deliverer'), bountyHourKey: '2020-01-01T00' }
    const claimed: PlayerSave = {
      ...saveFor('deliverer'),
      bountyClaimedIds: [bounty.id],
    }
    return {
      // Syncing the hour wipes the counters, so the objective reads unfinished.
      staleHour: prepareBountyTurnIn(stale, bounty, NOW_MS),
      alreadyClaimed: prepareBountyTurnIn(claimed, bounty, NOW_MS),
      offBoard: prepareBountyTurnIn(saveFor('deliverer'), { ...bounty, id: 'BNT-9999' }, NOW_MS),
    } as unknown as JsonValue
  }),
]
