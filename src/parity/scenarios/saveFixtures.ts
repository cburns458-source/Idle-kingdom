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
