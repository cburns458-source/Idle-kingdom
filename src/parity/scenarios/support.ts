import { configNumber } from '../../game/activity/gathering'
import { eligiblePoolEntries, isSelectableAction, pickWeightedAction } from '../../game/activity/pools'
import {
  applyRelativeDropChance,
  equippedRelativeDropChanceBonusPercent,
  parseRelativeDropChanceBonusPercent,
  totalRelativeDropChanceBonusPercent,
} from '../../game/loot/dropChance'
import { mulberry32 } from '../../game/rng/mulberry32'
import type { PlayerSave } from '../../game/save/types'
import { scenario, type JsonValue, type ParityScenario } from '../types'
import { contentDatabase } from './contentDatabase'
import { asJson, baseSave, gearedSave, richSave } from './saveFixtures'

type SaveKind = 'base' | 'rich' | 'geared'

function saveFor(kind: SaveKind): PlayerSave {
  const db = contentDatabase()
  if (kind === 'base') return baseSave(db)
  if (kind === 'rich') return richSave(db)
  return gearedSave(db)
}

const CONFIG_KEYS = [
  'starting_max_hp',
  'unarmed_min_damage',
  'unarmed_max_damage',
  'damage_floor',
  'currency_item_id',
  'database_scope',
  'not_a_key',
]

const CAPABILITY_STRINGS = [
  '+15% relative Drop Chance',
  'artisanry_output; special_effect; +15% relative Drop Chance',
  '+10% relative drop chance; +5% relative Drop Chance',
  '+2.5% relative Drop Chance',
  'relative Drop Chance',
  '',
  null,
]

const DROP_CHANCE_CASES: Array<[number | null, number]> = [
  [10, 0],
  [10, 15],
  [90, 50],
  [100, 25],
  [0, 15],
  [null, 15],
]

const PICK_SEED = 987654321
const PICK_COUNT = 16

/**
 * Strings whose ordering differs between JavaScript's locale-aware compare and
 * Dart's code-unit `compareTo`. Recording Node's answers pins the Dart
 * approximation in `js_compat.dart`.
 */
const LOCALE_PAIRS: Array<[string, string]> = [
  ['apple', 'Banana'],
  ['Banana', 'apple'],
  ['apple', 'Apple'],
  ['Apple', 'apple'],
  ['apple', 'apple'],
  ['Wood Elf', 'wood elf'],
  ['Wood Axe', 'Wood-Axe'],
  ['RST-0001', 'RST-0010'],
  ['RST-0002', 'RST-00020'],
  ['a', 'ab'],
  ['Zebra', 'apple'],
  ["Chef's Hat", 'Chefs Hat'],
  ['1 Coin', 'A Coin'],
]

export const supportScenarios: ParityScenario[] = [
  scenario('config/numbers', 'keys', { source: 'content', keys: CONFIG_KEYS }, () => {
    const db = contentDatabase()
    return { values: CONFIG_KEYS.map((key) => configNumber(db, key, -1)) }
  }),

  scenario('pools/selectable', 'all-actions', { source: 'content' }, () => {
    const db = contentDatabase()
    return {
      actions: db.Actions.map((action) => ({
        actionId: action['Action ID'],
        selectable: isSelectableAction(action),
      })),
    } as unknown as JsonValue
  }),

  scenario('pools/eligible', 'all-pools', { source: 'content' }, () => {
    const db = contentDatabase()
    const poolIds = [...new Set(db.PoolEntries.map((entry) => entry['Pool ID']))]
    return {
      pools: poolIds.map((poolId) => ({
        poolId,
        actionIds: eligiblePoolEntries(db, poolId).map((pair) => pair.action['Action ID']),
      })),
    } as unknown as JsonValue
  }),

  scenario(
    'pools/pick',
    'seeded-draws',
    { source: 'content', seed: PICK_SEED, count: PICK_COUNT, poolId: 'POOL-0001' },
    () => {
      const db = contentDatabase()
      const entries = eligiblePoolEntries(db, 'POOL-0001')
      const random = mulberry32(PICK_SEED)
      return {
        picks: Array.from(
          { length: PICK_COUNT },
          () => pickWeightedAction(entries, random)?.['Action ID'] ?? null,
        ),
        empty: pickWeightedAction([], mulberry32(PICK_SEED))?.['Action ID'] ?? null,
      }
    },
  ),

  scenario(
    'loot/drop-chance-tags',
    'capability-strings',
    { source: 'content', strings: CAPABILITY_STRINGS },
    () => ({
      parsed: CAPABILITY_STRINGS.map((value) => parseRelativeDropChanceBonusPercent(value)),
      allEquipment: contentDatabase().Equipment.map((row) => ({
        itemId: row['Item ID'],
        bonus: parseRelativeDropChanceBonusPercent(row['Capabilities / Effects']),
      })),
    }) as unknown as JsonValue,
  ),

  ...(['base', 'rich', 'geared'] as const).map((kind) =>
    scenario(
      'loot/drop-chance',
      kind,
      { source: 'content', save: asJson(saveFor(kind)) },
      () => {
        const db = contentDatabase()
        const save = saveFor(kind)
        return {
          equipped: equippedRelativeDropChanceBonusPercent(db, save),
          total: totalRelativeDropChanceBonusPercent(db, save),
        }
      },
    ),
  ),

  scenario(
    'loot/drop-chance',
    'apply-relative',
    { source: 'content', cases: DROP_CHANCE_CASES },
    () => ({
      results: DROP_CHANCE_CASES.map(([base, bonus]) => applyRelativeDropChance(base, bonus)),
    }),
  ),

  scenario(
    'js-compat/locale-compare',
    'pairs',
    { source: 'content', pairs: LOCALE_PAIRS },
    () => ({
      signs: LOCALE_PAIRS.map(([left, right]) => Math.sign(left.localeCompare(right))),
      sortedItemNames: contentDatabase()
        .Items.map((row) => row['Display Name'])
        .sort((left, right) => left.localeCompare(right)),
    }),
  ),
]
