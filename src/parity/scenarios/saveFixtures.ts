import type { GameDatabase } from '../../game/data/types'
import { createNewSave } from '../../game/save/saveStore'
import type { PlayerSave } from '../../game/save/types'
import type { JsonValue } from '../types'

const FIXED_TIMESTAMP = '2026-01-01T00:00:00.000Z'

/**
 * A new save with the clock pinned, so fixtures stay reproducible.
 *
 * Dart replays read the save straight out of the fixture input, which also
 * proves the generated model round-trips every field.
 */
export function baseSave(db: GameDatabase): PlayerSave {
  return pinTimestamps(createNewSave(db))
}

const ISO_TIMESTAMP = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/

/**
 * Replaces every clock-derived timestamp with a fixed one.
 *
 * Matching on shape rather than on a list of field names means a new
 * `nowIso()` field cannot quietly make fixtures unreproducible.
 */
function pinTimestamps<T>(value: T): T {
  if (typeof value === 'string') {
    return (ISO_TIMESTAMP.test(value) ? FIXED_TIMESTAMP : value) as T
  }
  if (Array.isArray(value)) return value.map((entry) => pinTimestamps(entry)) as T
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>).map(([key, entry]) => [
        key,
        pinTimestamps(entry),
      ]),
    ) as T
  }
  return value
}

/** A save with progress, so rules see non-empty skills, bag, and equipment. */
export function richSave(db: GameDatabase): PlayerSave {
  const base = baseSave(db)
  return {
    ...base,
    characterName: 'Parity',
    raceId: 'RACE-0001',
    gold: 12_345,
    currentLocationId: 'LOC-0002',
    skills: base.skills.map((skill, index) => {
      if (index === 0) return { ...skill, level: 12, xp: 1_500 }
      if (index === 1) return { ...skill, level: 3, xp: 120 }
      return skill
    }),
    inventory: [
      { itemId: 'ITEM-0025', quantity: 40 },
      { itemId: 'ITEM-0058', quantity: 5, favorite: true },
      { itemId: 'ITEM-0100', quantity: 1 },
      { itemId: 'ITEM-0100', quantity: 1, enchantmentId: 'ENCH-0001' },
      { itemId: 'ITEM-0108', quantity: 2, favorite: true },
    ],
    equipment: {
      slots: {
        ...base.equipment.slots,
        'SLOT-0001': { itemId: 'ITEM-0100', quantity: 1 },
      },
    },
    statistics: { values: { gold_earned: 500, actions_completed: 42 } },
  }
}

/**
 * A save wearing gear in most slots, so equipment / combat / spell rules have
 * something to read: enchanted weapon, off-hand dagger, two stacked spells, an
 * active combat potion, and a race with a max-HP bonus.
 */
export function gearedSave(db: GameDatabase): PlayerSave {
  const base = baseSave(db)
  return {
    ...base,
    characterName: 'Geared',
    raceId: 'RACE-0003',
    gold: 5_000,
    currentLocationId: 'LOC-0002',
    skills: base.skills.map((skill) =>
      skill.skillId === 'SKL-0001' ? { ...skill, level: 25, xp: 8_000 } : { ...skill, level: 20, xp: 4_500 },
    ),
    inventory: [
      { itemId: 'ITEM-0114', quantity: 1 },
      { itemId: 'ITEM-0129', quantity: 1 },
      { itemId: 'ITEM-0059', quantity: 12 },
      { itemId: 'ITEM-0295', quantity: 1 },
      { itemId: 'ITEM-0180', quantity: 1 },
      { itemId: 'ITEM-0170', quantity: 2 },
      { itemId: 'ITEM-0100', quantity: 1, enchantmentId: 'ENCH-0002' },
      { itemId: 'ITEM-0070', quantity: 3, favorite: true },
      // Gathering tools of two tiers each, so auto-equip has something to rank.
      { itemId: 'ITEM-0102', quantity: 1 },
      { itemId: 'ITEM-0115', quantity: 1 },
      { itemId: 'ITEM-0112', quantity: 1 },
      { itemId: 'ITEM-0108', quantity: 1 },
    ],
    equipment: {
      slots: {
        ...base.equipment.slots,
        'SLOT-0001': { itemId: 'ITEM-0130', quantity: 1, enchantmentId: 'ENCH-0003' },
        'SLOT-0002': { itemId: 'ITEM-0125', quantity: 1 },
        'SLOT-0003': { itemId: 'ITEM-0160', quantity: 1, enchantmentId: 'ENCH-0006' },
        'SLOT-0008': { itemId: 'ITEM-0180', quantity: 1 },
        'SLOT-0011': { itemId: 'ITEM-0058', quantity: 4 },
        'SLOT-0013': { itemId: 'ITEM-0295', quantity: 1 },
        'SLOT-0014': { itemId: 'ITEM-0295', quantity: 1 },
        'SLOT-0015': { itemId: 'ITEM-0297', quantity: 1 },
      },
    },
    activePotionEffect: {
      scope: 'one_combat_encounter',
      itemId: 'ITEM-0072',
      damageBonusPercent: 10,
      enemyMaxHpDamagePercent: null,
      relativeDropChanceBonusPercent: null,
      baseDurationReductionPercent: null,
    },
  }
}

/** A bag filled to the slot limit, for overflow cases. */
export function fullBagSave(db: GameDatabase, items: string[]): PlayerSave {
  const base = baseSave(db)
  const inventory = Array.from({ length: 180 }, (_, index) => ({
    itemId: items[index % items.length]!,
    quantity: 1,
    enchantmentId: `ENCH-${String(index).padStart(4, '0')}`,
  }))
  return { ...base, inventory }
}

export function asJson(save: PlayerSave): JsonValue {
  return save as unknown as JsonValue
}
