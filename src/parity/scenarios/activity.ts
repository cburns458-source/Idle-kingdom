import { bonusSkillXpForAction, bowHuntingCombatXpBonus } from '../../game/activity/bonusXp'
import {
  activityStillValid,
  beginActivitySave,
  clearActivitySave,
  completeGatheringAction,
  generateNextAction,
  getActivity,
  restoreActiveActionState,
  validateActivityStart,
} from '../../game/activity/engine'
import {
  gatheringDurationMs,
  gatheringXpReward,
  isBelowProficiency,
} from '../../game/activity/gathering'
import { resolveActionRewards } from '../../game/activity/rewards'
import { summarizeXpReward } from '../../game/activity/rewardSummary'
import {
  beginTravelActivityChange,
  clearActivityTransition,
  hasRunningPrimaryActivity,
  requestActivityStart,
  requestActivityStop,
  requestProductionStart,
  resolveActivityTransitions,
  stopPrimaryActivityNow,
} from '../../game/activity/transition'
import {
  applyPotionDropChance,
  applyPotionDurationMs,
  applyPotionEnemyRoundDamage,
  clearActivePotionEffect,
  parsePotionEffect,
  tryConsumePotionForScope,
} from '../../game/potions/effects'
import { mulberry32 } from '../../game/rng/mulberry32'
import type { ActivityTransition, PlayerSave } from '../../game/save/types'
import { scenario, type JsonValue, type ParityScenario } from '../types'
import { contentDatabase } from './contentDatabase'
import {
  asJson,
  baseSave,
  combatSave,
  gearedSave,
  kitchenSave,
  queuedProductionSave,
  richSave,
} from './saveFixtures'

type SaveKind = 'base' | 'rich' | 'geared' | 'kitchen' | 'queued' | 'combat'

function saveFor(kind: SaveKind): PlayerSave {
  const db = contentDatabase()
  if (kind === 'base') return baseSave(db)
  if (kind === 'rich') return richSave(db)
  if (kind === 'geared') return gearedSave(db)
  if (kind === 'kitchen') return kitchenSave(db)
  if (kind === 'queued') return queuedProductionSave(db)
  return combatSave(db)
}

function withSave(kind: SaveKind, extra: Record<string, JsonValue> = {}): JsonValue {
  return { source: 'content', save: asJson(saveFor(kind)), ...extra }
}

const NOW_MS = Date.parse('2026-01-01T00:00:00.000Z')
const NOW_ISO = '2026-01-01T00:00:00.000Z'
const SEED = 20260101

/** Gathering, combat, production, and citadel activities. */
const ACTIVITY_IDS = [
  'ACT-0001',
  'ACT-0002',
  'ACT-0010',
  'ACT-0017',
  'ACT-0028',
  'ACT-0032',
  'ACT-0033',
  'ACT-9999',
]

/** A combat action, two single-drop gathers, and a gather with a secondary table. */
const GATHERING_ACTIONS = ['ACN-0001', 'ACN-0028', 'ACN-0046', 'ACN-0018']
const POTION_ITEMS = ['ITEM-0070', 'ITEM-0071', 'ITEM-0072', 'ITEM-0073', 'ITEM-0100']

/** Saves standing where each activity lives, so validation reaches its later gates. */
function atLocation(kind: SaveKind, locationId: string): PlayerSave {
  return { ...saveFor(kind), currentLocationId: locationId }
}

/** Still recovering from defeat, which blocks every activity change. */
function deathPausedSave(): PlayerSave {
  return { ...saveFor('combat'), deathPauseUntil: '2026-01-01T00:00:30.000Z' }
}

export const activityScenarios: ParityScenario[] = [
  ...(['base', 'geared', 'kitchen'] as const).map((kind) =>
    scenario('activity/validate', kind, withSave(kind, { activityIds: ACTIVITY_IDS }), () => {
      const db = contentDatabase()
      return {
        byActivity: ACTIVITY_IDS.map((activityId) => {
          const activity = getActivity(db, activityId)
          const save = activity
            ? atLocation(kind, activity['Location ID'])
            : saveFor(kind)
          return {
            activityId,
            found: activity != null,
            atOwnLocation: validateActivityStart(db, save, activityId),
            elsewhere: validateActivityStart(db, saveFor(kind), activityId),
            stillValid: activityStillValid(db, save, activityId),
          }
        }),
      } as unknown as JsonValue
    }),
  ),

  ...(['base', 'geared'] as const).map((kind) =>
    scenario(
      'activity/gathering',
      `durations-and-xp-${kind}`,
      withSave(kind, { actionIds: GATHERING_ACTIONS }),
      () => {
        const db = contentDatabase()
        const save = saveFor(kind)
        return {
          byAction: GATHERING_ACTIONS.map((actionId) => {
            const action = db.Actions.find((row) => row['Action ID'] === actionId)!
            return {
              actionId,
              duration: gatheringDurationMs(db, save, action),
              xp: gatheringXpReward(db, save, action),
              below: isBelowProficiency(save, action),
              overrideXp: gatheringXpReward(db, save, action, 100),
              zeroXp: gatheringXpReward(db, save, action, 0),
            }
          }),
        } as unknown as JsonValue
      },
    ),
  ),

  ...(['base', 'geared'] as const).map((kind) =>
    scenario('activity/bonus-xp', `grants-${kind}`, withSave(kind), () => {
      const db = contentDatabase()
      const save = saveFor(kind)
      return {
        byAction: db.Actions.map((action) => ({
          actionId: action['Action ID'],
          bonus: bonusSkillXpForAction(action),
        })).filter((row) => row.bonus != null),
        // A bow in the Weapon/Tool slot turns Hunting XP into Combat XP too.
        hunting: bowHuntingCombatXpBonus(db, save, { 'Relevant Skill ID': 'SKL-0005' }, 400),
        nonHunting: bowHuntingCombatXpBonus(db, save, { 'Relevant Skill ID': 'SKL-0001' }, 400),
        zeroXp: bowHuntingCombatXpBonus(db, save, { 'Relevant Skill ID': 'SKL-0005' }, 0),
      } as unknown as JsonValue
    }),
  ),

  scenario('activity/reward-summary', 'lines', withSave('rich'), () => {
    const db = contentDatabase()
    const save = saveFor('rich')
    return {
      lines: ['SKL-0001', 'SKL-0007', 'SKL-9999'].flatMap((skillId) => [
        summarizeXpReward(db, save, skillId, 120, null),
        summarizeXpReward(db, save, skillId, 120, 14),
        summarizeXpReward(db, save, skillId, 0, null),
      ]),
    } as unknown as JsonValue
  }),

  ...(['base', 'geared'] as const).flatMap((kind) =>
    GATHERING_ACTIONS.map((actionId) =>
      scenario(
        'activity/rewards',
        `${kind}-${actionId.toLowerCase()}`,
        withSave(kind, { actionId, seed: SEED }),
        () => {
          const db = contentDatabase()
          const action = db.Actions.find((row) => row['Action ID'] === actionId)!
          const rewarded = resolveActionRewards(db, saveFor(kind), action, mulberry32(SEED))
          return {
            save: asJson(rewarded.save),
            loot: rewarded.loot,
            goldGained: rewarded.goldGained,
          } as unknown as JsonValue
        },
      ),
    ),
  ),

  ...(['base', 'geared'] as const).flatMap((kind) =>
    GATHERING_ACTIONS.map((actionId) =>
      scenario(
        'activity/complete',
        `${kind}-${actionId.toLowerCase()}`,
        withSave(kind, { actionId, seed: SEED }),
        () => {
          const db = contentDatabase()
          const action = db.Actions.find((row) => row['Action ID'] === actionId)!
          const completed = completeGatheringAction(db, saveFor(kind), action, mulberry32(SEED))
          return {
            save: asJson(completed.save),
            result: completed.result,
          } as unknown as JsonValue
        },
      ),
    ),
  ),

  ...(['ACT-0001', 'ACT-0002', 'ACT-0032', 'ACT-0017'] as const).map((activityId) =>
    scenario(
      'activity/generate',
      activityId.toLowerCase(),
      withSave('geared', { activityId, seed: SEED, nowMs: NOW_MS }),
      () => {
        const db = contentDatabase()
        const activity = getActivity(db, activityId)
        const save = activity ? atLocation('geared', activity['Location ID']) : saveFor('geared')
        const generated = generateNextAction(db, save, activityId, mulberry32(SEED), NOW_MS)
        return (generated == null
          ? null
          : {
              actionId: generated.action['Action ID'],
              state: generated.state,
              save: asJson(generated.save),
            }) as unknown as JsonValue
      },
    ),
  ),

  scenario('activity/save-state', 'begin-clear-restore', withSave('queued', { nowIso: NOW_ISO }), () => {
    const queued = saveFor('queued')
    const begun = beginActivitySave(queued, 'ACT-0001', NOW_ISO)
    const cleared = clearActivitySave(begun, NOW_MS)
    return {
      begun: asJson(begun),
      cleared: asJson(cleared),
      restored: restoreActiveActionState(queued),
      restoredEmpty: restoreActiveActionState(cleared),
      running: [hasRunningPrimaryActivity(queued), hasRunningPrimaryActivity(cleared)],
    } as unknown as JsonValue
  }),

  ...(['base', 'geared', 'kitchen', 'queued'] as const).map((kind) =>
    scenario(
      'activity/transition',
      `stop-${kind}`,
      withSave(kind, { nowMs: NOW_MS }),
      () => {
        const db = contentDatabase()
        const save = saveFor(kind)
        const stop = requestActivityStop(db, save, NOW_MS)
        return {
          stopNow: asJson(stopPrimaryActivityNow(db, save, NOW_MS)),
          travel: asJson(beginTravelActivityChange(db, save, NOW_MS)),
          request: (stop.ok ? { ok: true, save: asJson(stop.save) } : stop) as JsonValue,
          clearedTransition: asJson(clearActivityTransition(save)),
        }
      },
    ),
  ),

  ...(['ACT-0001', 'ACT-0032', 'ACT-0017', 'ACT-9999'] as const).map((activityId) =>
    scenario(
      'activity/request-start',
      activityId.toLowerCase(),
      withSave('geared', { activityId, seed: SEED, nowMs: NOW_MS }),
      () => {
        const db = contentDatabase()
        const activity = getActivity(db, activityId)
        const save = activity ? atLocation('geared', activity['Location ID']) : saveFor('geared')
        const started = requestActivityStart(db, save, activityId, NOW_MS, mulberry32(SEED))
        return (started.ok
          ? { ok: true, save: asJson(started.save) }
          : started) as unknown as JsonValue
      },
    ),
  ),

  scenario(
    'activity/request-start',
    'death-paused',
    {
      source: 'content',
      save: asJson(deathPausedSave()),
      activityId: 'ACT-0002',
      nowMs: NOW_MS,
    },
    () => {
      const db = contentDatabase()
      const save = deathPausedSave()
      const started = requestActivityStart(db, save, 'ACT-0002', NOW_MS, mulberry32(SEED))
      const stopped = requestActivityStop(db, save, NOW_MS)
      return {
        start: started as unknown as JsonValue,
        stop: stopped as unknown as JsonValue,
        stopNow: asJson(stopPrimaryActivityNow(db, save, NOW_MS)),
      }
    },
  ),

  ...([
    { name: 'ok', recipeId: 'RCP-0001', quantity: 2 },
    { name: 'unknown-recipe', recipeId: 'RCP-9999', quantity: 2 },
    { name: 'no-materials', recipeId: 'RCP-0002', quantity: 9 },
  ] as const).map((entry) =>
    scenario(
      'activity/request-production',
      entry.name,
      withSave('kitchen', {
        activityId: 'ACT-0017',
        recipeId: entry.recipeId,
        quantity: entry.quantity,
        nowMs: NOW_MS,
      }),
      () => {
        const started = requestProductionStart(
          contentDatabase(),
          saveFor('kitchen'),
          'ACT-0017',
          entry.recipeId,
          entry.quantity,
          NOW_MS,
        )
        return (started.ok
          ? { ok: true, save: asJson(started.save) }
          : started) as unknown as JsonValue
      },
    ),
  ),

  // Legacy saves can still carry a queued transition; resolving applies it now.
  ...([
    {
      name: 'starting-pool',
      transition: {
        kind: 'starting',
        activityId: 'ACT-0001',
        followUpActivityId: null,
        startedAt: NOW_ISO,
        durationMs: 5_000,
      },
      locationId: 'LOC-0001',
    },
    {
      name: 'stopping-followup-production',
      transition: {
        kind: 'stopping',
        activityId: 'ACT-0017',
        followUpActivityId: 'ACT-0017',
        productionRecipeId: 'RCP-0001',
        productionQuantity: 2,
        startedAt: NOW_ISO,
        durationMs: 5_000,
      },
      locationId: 'LOC-0023',
    },
    {
      name: 'stopping-followup-station-without-recipe',
      transition: {
        kind: 'stopping',
        activityId: 'ACT-0017',
        followUpActivityId: 'ACT-0017',
        startedAt: NOW_ISO,
        durationMs: 5_000,
      },
      locationId: 'LOC-0023',
    },
  ] as Array<{ name: string; transition: ActivityTransition; locationId: string }>).map((entry) =>
    scenario(
      'activity/resolve-transitions',
      entry.name,
      { source: 'content', nowMs: NOW_MS, seed: SEED, save: asJson({
        ...kitchenSave(contentDatabase()),
        currentLocationId: entry.locationId,
        activityTransition: entry.transition,
      }) },
      () => {
        const save: PlayerSave = {
          ...kitchenSave(contentDatabase()),
          currentLocationId: entry.locationId,
          activityTransition: entry.transition,
        }
        return {
          resolved: asJson(
            resolveActivityTransitions(contentDatabase(), save, NOW_MS, mulberry32(SEED)),
          ),
        }
      },
    ),
  ),

  scenario('potions/effects', 'parse', { source: 'content', itemIds: POTION_ITEMS }, () => {
    const db = contentDatabase()
    return {
      parsed: POTION_ITEMS.map((itemId) => ({
        itemId,
        effect: parsePotionEffect(
          db.Equipment.find((row) => row['Item ID'] === itemId),
          itemId,
        ),
      })),
      missingRow: parsePotionEffect(undefined, 'ITEM-0070'),
    } as unknown as JsonValue
  }),

  ...(['one_action', 'one_combat_encounter', 'one_standard_production_action'] as const).map((scope) =>
    scenario(
      'potions/consume',
      scope.replaceAll('_', '-'),
      withSave('kitchen', { scope }),
      () => {
        const db = contentDatabase()
        const kitchen = saveFor('kitchen')
        const consumed = tryConsumePotionForScope(db, kitchen, scope)
        // One potion left, so consuming it has to empty the slot.
        const lastOne = tryConsumePotionForScope(
          db,
          {
            ...kitchen,
            equipment: {
              slots: { ...kitchen.equipment.slots, 'SLOT-0012': { itemId: 'ITEM-0071', quantity: 1 } },
            },
          },
          scope,
        )
        const emptySlot = tryConsumePotionForScope(
          db,
          { ...kitchen, equipment: { slots: { ...kitchen.equipment.slots, 'SLOT-0012': null } } },
          scope,
        )
        return {
          consumed: {
            save: asJson(consumed.save),
            consumed: consumed.consumed,
            effect: consumed.effect,
            potionName: consumed.potionName,
          },
          lastOne: { save: asJson(lastOne.save), consumed: lastOne.consumed },
          emptySlot: { save: asJson(emptySlot.save), consumed: emptySlot.consumed },
          cleared: asJson(clearActivePotionEffect(consumed.save)),
        } as unknown as JsonValue
      },
    ),
  ),

  scenario('potions/apply', 'modifiers', { source: 'content' }, () => {
    const db = contentDatabase()
    const dropEffect = parsePotionEffect(
      db.Equipment.find((row) => row['Item ID'] === 'ITEM-0070'),
      'ITEM-0070',
    )
    const durationEffect = parsePotionEffect(
      db.Equipment.find((row) => row['Item ID'] === 'ITEM-0071'),
      'ITEM-0071',
    )
    const poisonEffect = parsePotionEffect(
      db.Equipment.find((row) => row['Item ID'] === 'ITEM-0073'),
      'ITEM-0073',
    )
    return {
      dropChance: [10, 90, 0, null].map((base) => applyPotionDropChance(base, dropEffect)),
      dropChanceNoEffect: applyPotionDropChance(10, null),
      durations: [0, 1_000, 20_000, 33_333].map((ms) => applyPotionDurationMs(ms, durationEffect)),
      durationsNoEffect: [20_000].map((ms) => applyPotionDurationMs(ms, null)),
      poison: [0, 100, 1_250].map((hp) => applyPotionEnemyRoundDamage(hp, hp || 100, poisonEffect)),
      poisonFloor: applyPotionEnemyRoundDamage(100, 1_000, poisonEffect),
      poisonNoEffect: applyPotionEnemyRoundDamage(1_250, 1_250, durationEffect),
    } as unknown as JsonValue
  }),
]
