import {
  beginProductionQueue,
  cancelProductionActivity,
  clearProductionSave,
  completeProductionCraft,
  resolveProductionProgress,
} from '../../game/production/engine'
import { removeIngredients } from '../../game/production/inventory'
import {
  clampProductionQuantity,
  facilityIdForActivity,
  getRecipe,
  inventoryCount,
  isCompleteRecipe,
  isStandardProductionActivity,
  maxCraftsFromMaterials,
  maxCraftsFromQueueCap,
  projectFacilityIdForLookup,
  queueCapSeconds,
  recipeFacilityIdForLookup,
  recipeIngredients,
  recipeMatchesFacility,
  recipesForActivity,
} from '../../game/production/recipes'
import {
  isAutomaticLevelUnlock,
  knowsProject,
  knowsRecipe,
  listRecipeBookEntries,
  unlockRecipeId,
} from '../../game/recipes/knowledge'
import type { PlayerSave } from '../../game/save/types'
import { scenario, type JsonValue, type ParityScenario } from '../types'
import { contentDatabase } from './contentDatabase'
import { asJson, baseSave, kitchenSave, queuedProductionSave, richSave } from './saveFixtures'

type SaveKind = 'base' | 'rich' | 'kitchen' | 'queued'

function saveFor(kind: SaveKind): PlayerSave {
  const db = contentDatabase()
  if (kind === 'base') return baseSave(db)
  if (kind === 'rich') return richSave(db)
  if (kind === 'kitchen') return kitchenSave(db)
  return queuedProductionSave(db)
}

function withSave(kind: SaveKind, extra: Record<string, JsonValue> = {}): JsonValue {
  return { source: 'content', save: asJson(saveFor(kind)), ...extra }
}

/** Every facility id the sharing tables remap, plus one that is not remapped. */
const FACILITY_IDS = [
  'FAC-0001',
  'FAC-0003',
  'FAC-0005',
  'FAC-0010',
  'FAC-0012',
  'FAC-0013',
  'FAC-0014',
  'FAC-0015',
  'FAC-0016',
  'FAC-9999',
]

const PRODUCTION_ACTIVITY_IDS = ['ACT-0017', 'ACT-0018', 'ACT-0020', 'ACT-0028', 'ACT-0001']

const CLAMP_CASES: Array<[string, number]> = [
  ['RCP-0001', 1],
  ['RCP-0001', 10],
  ['RCP-0001', 5000],
  ['RCP-0001', 0],
  ['RCP-0001', -3],
  ['RCP-0001', 2.7],
  ['RCP-0003', 4],
]

/** now = the pinned fixture timestamp, so queue starts are reproducible. */
const NOW_MS = Date.parse('2026-01-01T00:00:00.000Z')

const QUEUE_CASES: Array<{
  name: string
  save: SaveKind
  activityId: string
  recipeId: string
  quantity: number
}> = [
  { name: 'ok', save: 'kitchen', activityId: 'ACT-0017', recipeId: 'RCP-0001', quantity: 3 },
  { name: 'ok-full-stack', save: 'kitchen', activityId: 'ACT-0017', recipeId: 'RCP-0001', quantity: 25 },
  { name: 'unknown-recipe', save: 'kitchen', activityId: 'ACT-0017', recipeId: 'RCP-9999', quantity: 1 },
  { name: 'unlearned', save: 'base', activityId: 'ACT-0017', recipeId: 'RCP-0003', quantity: 1 },
  { name: 'wrong-station', save: 'kitchen', activityId: 'ACT-0017', recipeId: 'RCP-0014', quantity: 1 },
  { name: 'zero-quantity', save: 'kitchen', activityId: 'ACT-0017', recipeId: 'RCP-0001', quantity: 0 },
  { name: 'over-cap', save: 'kitchen', activityId: 'ACT-0017', recipeId: 'RCP-0001', quantity: 100_000 },
  { name: 'missing-materials', save: 'kitchen', activityId: 'ACT-0017', recipeId: 'RCP-0002', quantity: 9 },
  // Citadel kitchen shares the Town recipe book through the facility alias table.
  { name: 'shared-facility', save: 'kitchen', activityId: 'ACT-0028', recipeId: 'RCP-0001', quantity: 2 },
]

export const productionScenarios: ParityScenario[] = [
  scenario('production/recipes', 'all-rows', { source: 'content' }, () => {
    const db = contentDatabase()
    return {
      rows: db.Recipes.map((recipe) => ({
        recipeId: recipe['Recipe ID'],
        complete: isCompleteRecipe(recipe),
        ingredients: recipeIngredients(recipe),
        queueCap: maxCraftsFromQueueCap(db, recipe),
        automatic: isAutomaticLevelUnlock(recipe),
      })),
      queueCapSeconds: queueCapSeconds(db),
    } as unknown as JsonValue
  }),

  scenario(
    'production/facility-lookup',
    'aliases',
    { source: 'content', facilityIds: FACILITY_IDS },
    () => ({
      recipeLookup: FACILITY_IDS.map((facilityId) => recipeFacilityIdForLookup(facilityId)),
      projectLookup: FACILITY_IDS.map((facilityId) => projectFacilityIdForLookup(facilityId)),
      matches: FACILITY_IDS.map((facilityId) => recipeMatchesFacility('FAC-0001', facilityId)),
    }),
  ),

  scenario('production/activities', 'all-rows', { source: 'content' }, () => {
    const db = contentDatabase()
    return {
      rows: db.Activities.map((activity) => ({
        activityId: activity['Activity ID'],
        facilityId: facilityIdForActivity(db, activity['Activity ID']),
        standardProduction: isStandardProductionActivity(db, activity),
      })),
    } as unknown as JsonValue
  }),

  ...(['base', 'rich', 'kitchen'] as const).map((kind) =>
    scenario('production/available', kind, withSave(kind, { activityIds: PRODUCTION_ACTIVITY_IDS }), () => {
      const db = contentDatabase()
      const save = saveFor(kind)
      return {
        byActivity: PRODUCTION_ACTIVITY_IDS.map((activityId) => ({
          activityId,
          recipeIds: recipesForActivity(db, save, activityId).map((recipe) => recipe['Recipe ID']),
        })),
        counts: [
          inventoryCount(save, 'ITEM-0025'),
          inventoryCount(save, 'ITEM-0047'),
          inventoryCount(save, 'ITEM-9999'),
        ],
        materialMax: ['RCP-0001', 'RCP-0002', 'RCP-0014'].map((recipeId) => {
          const recipe = getRecipe(db, recipeId)
          return recipe ? maxCraftsFromMaterials(save, recipe) : null
        }),
      }
    }),
  ),

  scenario(
    'production/clamp',
    'quantities',
    withSave('kitchen', { cases: CLAMP_CASES }),
    () => {
      const db = contentDatabase()
      const save = saveFor('kitchen')
      return {
        results: CLAMP_CASES.map(([recipeId, requested]) => {
          const recipe = getRecipe(db, recipeId)
          return recipe ? clampProductionQuantity(db, save, recipe, requested) : null
        }),
      }
    },
  ),

  scenario('production/remove-ingredients', 'cases', withSave('kitchen'), () => {
    const save = saveFor('kitchen')
    const cases: Array<{ name: string; ingredients: Array<{ itemId: string; quantity: number }>; crafts: number }> = [
      { name: 'single', ingredients: [{ itemId: 'ITEM-0025', quantity: 1 }], crafts: 1 },
      { name: 'exact-empty', ingredients: [{ itemId: 'ITEM-0048', quantity: 1 }], crafts: 2 },
      { name: 'multi', ingredients: [
        { itemId: 'ITEM-0025', quantity: 2 },
        { itemId: 'ITEM-0047', quantity: 1 },
      ], crafts: 2 },
      { name: 'same-item-twice', ingredients: [
        { itemId: 'ITEM-0025', quantity: 10 },
        { itemId: 'ITEM-0025', quantity: 10 },
      ], crafts: 1 },
      { name: 'too-many', ingredients: [{ itemId: 'ITEM-0025', quantity: 100 }], crafts: 1 },
      { name: 'missing-item', ingredients: [{ itemId: 'ITEM-9999', quantity: 1 }], crafts: 1 },
      { name: 'zero-crafts', ingredients: [{ itemId: 'ITEM-0025', quantity: 1 }], crafts: 0 },
    ]
    return {
      results: cases.map((entry) => {
        const next = removeIngredients(save, entry.ingredients, entry.crafts)
        return { name: entry.name, save: next == null ? null : asJson(next) }
      }),
    } as unknown as JsonValue
  }),

  ...QUEUE_CASES.map((entry) =>
    scenario(
      'production/queue',
      entry.name,
      withSave(entry.save, {
        activityId: entry.activityId,
        recipeId: entry.recipeId,
        quantity: entry.quantity,
        nowMs: NOW_MS,
      }),
      () => {
        const queued = beginProductionQueue(
          contentDatabase(),
          saveFor(entry.save),
          entry.activityId,
          entry.recipeId,
          entry.quantity,
          NOW_MS,
        )
        return (queued.ok ? { ok: true, save: asJson(queued.save) } : queued) as unknown as JsonValue
      },
    ),
  ),

  scenario('production/craft', 'mid-queue', withSave('queued', { nowMs: NOW_MS + 20_000 }), () => {
    const completed = completeProductionCraft(contentDatabase(), saveFor('queued'), NOW_MS + 20_000)
    return (completed == null
      ? null
      : {
          save: asJson(completed.save),
          finishedQueue: completed.finishedQueue,
          xpGained: completed.xpGained,
          outputName: completed.outputName,
          outputQty: completed.outputQty,
          reward: completed.reward,
        }) as unknown as JsonValue
  }),

  scenario('production/craft', 'no-queue', withSave('kitchen', { nowMs: NOW_MS }), () => {
    const completed = completeProductionCraft(contentDatabase(), saveFor('kitchen'), NOW_MS)
    return completed == null ? null : ({ finishedQueue: completed.finishedQueue } as JsonValue)
  }),

  // Enough elapsed time to drain the whole queue in one resolve.
  ...[0, 20_000, 45_000, 600_000].map((elapsed) =>
    scenario(
      'production/progress',
      `elapsed-${elapsed}`,
      withSave('queued', { nowMs: NOW_MS + elapsed }),
      () => {
        const resolved = resolveProductionProgress(
          contentDatabase(),
          saveFor('queued'),
          NOW_MS + elapsed,
        )
        return {
          save: asJson(resolved.save),
          craftsCompleted: resolved.craftsCompleted,
          messages: resolved.messages,
          activityMs: resolved.activityMs,
        } as unknown as JsonValue
      },
    ),
  ),

  scenario('production/cancel', 'refunds-remaining', withSave('queued'), () => ({
    save: asJson(cancelProductionActivity(contentDatabase(), saveFor('queued'))),
    cleared: asJson(clearProductionSave(saveFor('queued'))),
  })),

  scenario('recipes/knowledge', 'all-rows', withSave('kitchen'), () => {
    const db = contentDatabase()
    const save = saveFor('kitchen')
    return {
      recipes: db.Recipes.map((recipe) => ({
        recipeId: recipe['Recipe ID'],
        known: knowsRecipe(save, db, recipe['Recipe ID']),
      })),
      projects: db.Projects.map((project) => ({
        projectId: project['Project ID'],
        known: knowsProject(save, db, project['Project ID']),
      })),
      unknownId: knowsRecipe(save, db, 'RCP-9999'),
    } as unknown as JsonValue
  }),

  scenario('recipes/knowledge', 'unlock', withSave('base'), () => {
    const save = saveFor('base')
    const once = unlockRecipeId(save, 'RCP-0003')
    return {
      once: asJson(once),
      twice: asJson(unlockRecipeId(once, 'RCP-0003')),
      blank: asJson(unlockRecipeId(save, '   ')),
    }
  }),

  ...(['base', 'kitchen'] as const).map((kind) =>
    scenario('recipes/book', kind, withSave(kind), () => ({
      entries: listRecipeBookEntries(saveFor(kind), contentDatabase()),
    }) as unknown as JsonValue),
  ),
]
