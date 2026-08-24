import {
  addItemToInventoryExact,
  addItemsToInventory,
} from '../../game/activity/rewards'
import {
  evaluateRequirement,
  isHardRequirement,
  requirementsForEntity,
  unmetHardRequirements,
} from '../../game/activity/requirements'
import { applyXp, getSkillProgress, levelForTotalXp, raiseSkillToMinimumLevel } from '../../game/activity/xp'
import { skillXpProgress } from '../../game/activity/xpProgress'
import { filterLaunchContent } from '../../game/data/validate'
import {
  canFitItemQuantity,
  inventorySlotCount,
  inventorySlotsFree,
  maxAddableQuantity,
} from '../../game/inventory/capacity'
import {
  depositToBank,
  locationHasBank,
  withdrawFromBank,
  type BankMoveResult,
} from '../../game/inventory/bank'
import { destroyInventoryIndexes } from '../../game/inventory/destroy'
import { sortInventoryFavoritesFirst, toggleInventoryFavorite } from '../../game/inventory/favorites'
import { totalLevel, totalSkillXp } from '../../game/skills/totals'
import type { PlayerSave } from '../../game/save/types'
import { scenario, type JsonValue, type ParityScenario } from '../types'
import { contentDatabase } from './contentDatabase'
import { asJson, baseSave, fullBagSave, richSave } from './saveFixtures'

/** Saves are carried in the fixture input, so Dart rebuilds the exact state. */
function withSave(save: PlayerSave, extra: Record<string, JsonValue> = {}): JsonValue {
  return { source: 'content', save: asJson(save), ...extra }
}

interface AddCase {
  name: string
  itemId: string
  quantity: number
  enchantmentId?: string | null
  favorite?: boolean
  save: 'base' | 'rich' | 'full'
}

const ADD_CASES: AddCase[] = [
  { name: 'gold-becomes-currency', itemId: 'ITEM-0001', quantity: 250, save: 'base' },
  { name: 'gold-with-enchantment-takes-a-slot', itemId: 'ITEM-0001', quantity: 2, enchantmentId: 'ENCH-0001', save: 'base' },
  { name: 'new-stack', itemId: 'ITEM-0025', quantity: 7, save: 'base' },
  { name: 'merges-existing-stack', itemId: 'ITEM-0025', quantity: 7, save: 'rich' },
  { name: 'favorite-add-merges-existing-stack', itemId: 'ITEM-0025', quantity: 3, favorite: true, save: 'rich' },
  { name: 'merges-into-favorited-stack', itemId: 'ITEM-0058', quantity: 3, save: 'rich' },
  { name: 'merges-favorited-stack', itemId: 'ITEM-0108', quantity: 4, favorite: true, save: 'rich' },
  { name: 'enchanted-adds-one-slot-each', itemId: 'ITEM-0100', quantity: 3, enchantmentId: 'ENCH-0002', save: 'rich' },
  { name: 'zero-quantity', itemId: 'ITEM-0025', quantity: 0, save: 'rich' },
  { name: 'negative-quantity', itemId: 'ITEM-0025', quantity: -5, save: 'rich' },
  { name: 'fractional-quantity-floors', itemId: 'ITEM-0025', quantity: 3.9, save: 'rich' },
  { name: 'full-bag-rejects-new-stack', itemId: 'ITEM-0025', quantity: 1, save: 'full' },
  { name: 'full-bag-rejects-enchanted', itemId: 'ITEM-0100', quantity: 1, enchantmentId: 'ENCH-0003', save: 'full' },
  { name: 'full-bag-still-takes-gold', itemId: 'ITEM-0001', quantity: 10, save: 'full' },
]

const CAPACITY_CASES = [
  { name: 'plain-item-empty-bag', itemId: 'ITEM-0025', enchantmentId: null, favorite: false, save: 'base' as const },
  { name: 'plain-item-existing-stack', itemId: 'ITEM-0025', enchantmentId: null, favorite: false, save: 'rich' as const },
  { name: 'favorited-variant', itemId: 'ITEM-0108', enchantmentId: null, favorite: true, save: 'rich' as const },
  { name: 'plain-add-uses-favorited-stack', itemId: 'ITEM-0058', enchantmentId: null, favorite: false, save: 'rich' as const },
  { name: 'gold', itemId: 'ITEM-0001', enchantmentId: null, favorite: false, save: 'rich' as const },
  { name: 'enchanted', itemId: 'ITEM-0100', enchantmentId: 'ENCH-0001', favorite: false, save: 'rich' as const },
  { name: 'full-bag', itemId: 'ITEM-0025', enchantmentId: null, favorite: false, save: 'full' as const },
]

const DESTROY_CASES: Array<{ name: string; indexes: number[] }> = [
  { name: 'single', indexes: [1] },
  { name: 'multiple-unsorted', indexes: [3, 0, 2] },
  { name: 'duplicates-and-out-of-range', indexes: [1, 1, 99, -1] },
  { name: 'float-integer-index', indexes: [2.0] },
  { name: 'fractional-index-ignored', indexes: [2.5] },
  { name: 'empty', indexes: [] },
]

const BANK_ACCESS_LOCATION_IDS = [
  'LOC-0034',
  'LOC-0035',
  'LOC-0002',
  'LOC-0013',
  'LOC-0027',
  'LOC-0024',
  'LOC-0014',
  'LOC-0028',
  'LOC-0009',
  'LOC-0003',
]

function bankMoveJson(result: BankMoveResult): JsonValue {
  return result.ok
    ? ({ ok: true, save: asJson(result.save) } as unknown as JsonValue)
    : { ok: false, reason: result.reason }
}

function withBankMove(
  save: PlayerSave,
  action: 'deposit' | 'withdraw',
  index: number,
  quantity: number,
): JsonValue {
  return withSave(save, { action, index, quantity })
}

const XP_TOTALS = [0, 1, 82, 83, 174, 1_000_000, 12_345.6]
const APPLY_XP_CASES = [
  { name: 'levels-up', skillId: 'SKL-0001', amount: 5_000 },
  { name: 'small-gain', skillId: 'SKL-0001', amount: 5 },
  { name: 'unknown-skill-is-created', skillId: 'SKL-9999', amount: 100 },
  { name: 'zero-is-a-no-op', skillId: 'SKL-0001', amount: 0 },
  { name: 'negative-is-a-no-op', skillId: 'SKL-0001', amount: -50 },
  { name: 'fractional-gain', skillId: 'SKL-0002', amount: 12.5 },
]
const RAISE_CASES = [
  { name: 'raises-to-level-5', skillId: 'SKL-0002', minLevel: 5 },
  { name: 'already-higher', skillId: 'SKL-0001', minLevel: 2 },
  { name: 'minimum-of-one-is-a-no-op', skillId: 'SKL-0002', minLevel: 1 },
  { name: 'missing-curve-row', skillId: 'SKL-0002', minLevel: 9_999 },
  { name: 'unknown-skill', skillId: 'SKL-9999', minLevel: 10 },
]

const REQUIREMENT_ENTITIES: Array<[string, string]> = [
  ['Activity', 'ACT-0001'],
  ['Activity', 'ACT-0012'],
  ['Action', 'ACN-0001'],
  ['Recipe', 'RCP-0001'],
  ['Location', 'LOC-0018'],
  ['Missing', 'NOPE-0000'],
]

function saveFor(kind: 'base' | 'rich' | 'full'): PlayerSave {
  const db = contentDatabase()
  if (kind === 'base') return baseSave(db)
  if (kind === 'rich') return richSave(db)
  return fullBagSave(db, ['ITEM-0100', 'ITEM-0108'])
}

export const coreRuleScenarios: ParityScenario[] = [
  scenario('save/roundtrip', 'new-save', withSave(saveFor('base')), () => ({
    save: asJson(saveFor('base')),
  })),
  scenario('save/roundtrip', 'rich-save', withSave(saveFor('rich')), () => ({
    save: asJson(saveFor('rich')),
  })),

  ...CAPACITY_CASES.map((entry) =>
    scenario(
      'inventory/capacity',
      entry.name,
      withSave(saveFor(entry.save), {
        itemId: entry.itemId,
        enchantmentId: entry.enchantmentId,
        favorite: entry.favorite,
      }),
      () => {
        const save = saveFor(entry.save)
        return {
          slotCount: inventorySlotCount(save),
          slotsFree: inventorySlotsFree(save),
          maxAddable: maxAddableQuantity(save, entry.itemId, entry.enchantmentId, entry.favorite),
          canFitOne: canFitItemQuantity(save, entry.itemId, 1, entry.enchantmentId, entry.favorite),
          canFitZero: canFitItemQuantity(save, entry.itemId, 0, entry.enchantmentId, entry.favorite),
          canFitMany: canFitItemQuantity(
            save,
            entry.itemId,
            1_000,
            entry.enchantmentId,
            entry.favorite,
          ),
        }
      },
    ),
  ),

  ...ADD_CASES.map((entry) =>
    scenario(
      'inventory/add',
      entry.name,
      withSave(saveFor(entry.save), {
        itemId: entry.itemId,
        quantity: entry.quantity,
        enchantmentId: entry.enchantmentId ?? null,
        favorite: entry.favorite ?? false,
      }),
      () => {
        const partial = addItemsToInventory(
          saveFor(entry.save),
          entry.itemId,
          entry.quantity,
          entry.enchantmentId ?? null,
          entry.favorite ?? false,
        )
        const exact = addItemToInventoryExact(
          saveFor(entry.save),
          entry.itemId,
          entry.quantity,
          entry.enchantmentId ?? null,
          entry.favorite ?? false,
        )
        return {
          added: partial.added,
          save: asJson(partial.save),
          exact: exact.ok
            ? { ok: true, save: asJson(exact.save) }
            : { ok: false, reason: exact.reason },
        } as unknown as JsonValue
      },
    ),
  ),

  ...DESTROY_CASES.map((entry) =>
    scenario(
      'inventory/destroy',
      entry.name,
      withSave(saveFor('rich'), { indexes: entry.indexes }),
      () => ({ save: asJson(destroyInventoryIndexes(saveFor('rich'), entry.indexes)) }),
    ),
  ),

  scenario(
    'inventory/bank',
    'deposit-partial',
    withBankMove(
      { ...saveFor('base'), inventory: [{ itemId: 'ITEM-0002', quantity: 5 }] },
      'deposit',
      0,
      3,
    ),
    () =>
      bankMoveJson(
        depositToBank(
          { ...saveFor('base'), inventory: [{ itemId: 'ITEM-0002', quantity: 5 }] },
          0,
          3,
        ),
      ),
  ),
  scenario(
    'inventory/bank',
    'deposit-merges-existing',
    withBankMove(
      {
        ...saveFor('base'),
        inventory: [{ itemId: 'ITEM-0002', quantity: 4 }],
        bank: [{ itemId: 'ITEM-0002', quantity: 10 }],
      },
      'deposit',
      0,
      4,
    ),
    () =>
      bankMoveJson(
        depositToBank(
          {
            ...saveFor('base'),
            inventory: [{ itemId: 'ITEM-0002', quantity: 4 }],
            bank: [{ itemId: 'ITEM-0002', quantity: 10 }],
          },
          0,
          4,
        ),
      ),
  ),
  scenario(
    'inventory/bank',
    'withdraw-partial',
    withBankMove(
      {
        ...saveFor('base'),
        inventory: [{ itemId: 'ITEM-0002', quantity: 1 }],
        bank: [{ itemId: 'ITEM-0002', quantity: 8 }],
      },
      'withdraw',
      0,
      3,
    ),
    () =>
      bankMoveJson(
        withdrawFromBank(
          {
            ...saveFor('base'),
            inventory: [{ itemId: 'ITEM-0002', quantity: 1 }],
            bank: [{ itemId: 'ITEM-0002', quantity: 8 }],
          },
          0,
          3,
        ),
      ),
  ),
  scenario(
    'inventory/bank',
    'gold-stays-on-you',
    withBankMove(
      { ...saveFor('base'), inventory: [{ itemId: 'ITEM-0001', quantity: 25 }] },
      'deposit',
      0,
      25,
    ),
    () =>
      bankMoveJson(
        depositToBank(
          { ...saveFor('base'), inventory: [{ itemId: 'ITEM-0001', quantity: 25 }] },
          0,
          25,
        ),
      ),
  ),
  scenario(
    'inventory/bank',
    'bank-full',
    withBankMove(
      { ...saveFor('full'), inventory: [{ itemId: 'ITEM-0002', quantity: 1 }], bank: saveFor('full').inventory },
      'deposit',
      0,
      1,
    ),
    () =>
      bankMoveJson(
        depositToBank(
          { ...saveFor('full'), inventory: [{ itemId: 'ITEM-0002', quantity: 1 }], bank: saveFor('full').inventory },
          0,
          1,
        ),
      ),
  ),
  scenario(
    'inventory/bank',
    'bag-full-on-withdraw',
    withBankMove(
      { ...saveFor('full'), bank: [{ itemId: 'ITEM-0002', quantity: 1 }] },
      'withdraw',
      0,
      1,
    ),
    () =>
      bankMoveJson(
        withdrawFromBank({ ...saveFor('full'), bank: [{ itemId: 'ITEM-0002', quantity: 1 }] }, 0, 1),
      ),
  ),
  scenario(
    'inventory/bank',
    'missing-stack',
    withBankMove(saveFor('base'), 'deposit', 99, 1),
    () => bankMoveJson(depositToBank(saveFor('base'), 99, 1)),
  ),
  scenario(
    'inventory/bank',
    'zero-quantity',
    withBankMove(
      { ...saveFor('base'), inventory: [{ itemId: 'ITEM-0002', quantity: 5 }] },
      'deposit',
      0,
      0,
    ),
    () =>
      bankMoveJson(
        depositToBank(
          { ...saveFor('base'), inventory: [{ itemId: 'ITEM-0002', quantity: 5 }] },
          0,
          0,
        ),
      ),
  ),
  scenario('inventory/bank-access', 'named-locations', {
    source: 'content',
    locationIds: BANK_ACCESS_LOCATION_IDS,
  }, () => {
    const db = contentDatabase()
    return {
      results: BANK_ACCESS_LOCATION_IDS.map((id) => {
        const location = db.Locations.find((row) => row['Location ID'] === id)
        return { id, hasBank: locationHasBank(location) }
      }),
    }
  }),

  ...[0, 1, 2, 4, 99, -1].map((index) =>
    scenario(
      'inventory/favorites',
      `toggle-index-${index}`,
      withSave(saveFor('rich'), { index }),
      () => {
        const toggled = toggleInventoryFavorite(saveFor('rich'), index)
        return { save: toggled == null ? null : asJson(toggled) } as unknown as JsonValue
      },
    ),
  ),
  scenario('inventory/favorites', 'sort-favorites-first', withSave(saveFor('rich')), () => ({
    save: asJson(sortInventoryFavoritesFirst(saveFor('rich'))),
  })),

  scenario('xp/level-for-total', 'curve-boundaries', { source: 'content', totals: XP_TOTALS }, () => {
    const db = contentDatabase()
    return { levels: XP_TOTALS.map((total) => levelForTotalXp(db, total)) }
  }),
  scenario('xp/progress', 'curve-boundaries', { source: 'content', totals: XP_TOTALS }, () => {
    const db = contentDatabase()
    return {
      progress: XP_TOTALS.map((total) => skillXpProgress(db, total)),
    } as unknown as JsonValue
  }),
  scenario('xp/progress', 'launch-view', { source: 'content', totals: XP_TOTALS }, () => {
    const db = filterLaunchContent(contentDatabase())
    return {
      progress: XP_TOTALS.map((total) => skillXpProgress(db, total)),
    } as unknown as JsonValue
  }),

  ...APPLY_XP_CASES.map((entry) =>
    scenario(
      'xp/apply',
      entry.name,
      withSave(saveFor('rich'), { skillId: entry.skillId, amount: entry.amount }),
      () => {
        const result = applyXp(saveFor('rich'), contentDatabase(), entry.skillId, entry.amount)
        return {
          leveledUpTo: result.leveledUpTo,
          progress: getSkillProgress(result.save, entry.skillId),
          save: asJson(result.save),
        } as unknown as JsonValue
      },
    ),
  ),

  ...RAISE_CASES.map((entry) =>
    scenario(
      'xp/raise-to-minimum',
      entry.name,
      withSave(saveFor('rich'), { skillId: entry.skillId, minLevel: entry.minLevel }),
      () => {
        const result = raiseSkillToMinimumLevel(
          saveFor('rich'),
          contentDatabase(),
          entry.skillId,
          entry.minLevel,
        )
        return {
          raised: result.raised,
          progress: getSkillProgress(result.save, entry.skillId),
          save: asJson(result.save),
        } as unknown as JsonValue
      },
    ),
  ),

  scenario('skills/totals', 'rich-save', withSave(saveFor('rich')), () => {
    const save = saveFor('rich')
    return { totalSkillXp: totalSkillXp(save), totalLevel: totalLevel(save) }
  }),
  scenario('skills/totals', 'new-save', withSave(saveFor('base')), () => {
    const save = saveFor('base')
    return { totalSkillXp: totalSkillXp(save), totalLevel: totalLevel(save) }
  }),

  // Every requirement row in the real database, against two different saves.
  ...(['base', 'rich'] as const).map((kind) =>
    scenario('requirements/evaluate', `all-rows-${kind}-save`, withSave(saveFor(kind)), () => {
      const db = contentDatabase()
      const save = saveFor(kind)
      return {
        results: db.Requirements.map((requirement) => ({
          requirementId: requirement['Requirement ID'],
          hard: isHardRequirement(requirement),
          ...evaluateRequirement(db, save, requirement),
        })),
      } as unknown as JsonValue
    }),
  ),

  ...REQUIREMENT_ENTITIES.map(([entityType, entityId]) =>
    scenario(
      'requirements/for-entity',
      `${entityType}-${entityId}`.toLowerCase(),
      withSave(saveFor('rich'), { entityType, entityId }),
      () => {
        const db = contentDatabase()
        const save = saveFor('rich')
        const rows = requirementsForEntity(db, entityType, entityId)
        return {
          requirementIds: rows.map((row) => row['Requirement ID']),
          unmet: unmetHardRequirements(db, save, rows),
        }
      },
    ),
  ),
]
