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

/**
 * At the Town Kitchen with cooking materials and a production speed potion, so
 * the recipe lists, queue caps, and potion duration cut all have real inputs.
 */
export function kitchenSave(db: GameDatabase): PlayerSave {
  const base = baseSave(db)
  return {
    ...base,
    characterName: 'Cook',
    raceId: 'RACE-0002',
    gold: 2_000,
    currentLocationId: 'LOC-0023',
    skills: base.skills.map((skill) =>
      skill.skillId === 'SKL-0007' ? { ...skill, level: 30, xp: 250_000 } : skill,
    ),
    inventory: [
      { itemId: 'ITEM-0025', quantity: 25 },
      { itemId: 'ITEM-0047', quantity: 4 },
      { itemId: 'ITEM-0048', quantity: 2 },
      { itemId: 'ITEM-0071', quantity: 1 },
    ],
    equipment: {
      slots: { ...base.equipment.slots, 'SLOT-0012': { itemId: 'ITEM-0071', quantity: 2 } },
    },
  }
}

/** Mid-queue production, with the current craft already due at the pinned clock. */
export function queuedProductionSave(db: GameDatabase): PlayerSave {
  const kitchen = kitchenSave(db)
  return {
    ...kitchen,
    currentActivityId: 'ACT-0017',
    activityStartedAt: FIXED_TIMESTAMP,
    productionRecipeId: 'RCP-0001',
    productionQuantityTotal: 4,
    productionQuantityRemaining: 3,
    currentActionId: 'ACN-0115',
    actionStartedAt: FIXED_TIMESTAMP,
    actionDurationMs: 20_000,
  }
}

/**
 * At the Smithing forge with mentor knowledge, bars, and gold, so project
 * validation exercises the pass path as well as the gates.
 */
export function forgeSave(db: GameDatabase): PlayerSave {
  const base = baseSave(db)
  return {
    ...base,
    characterName: 'Smith',
    raceId: 'RACE-0004',
    gold: 50_000,
    currentLocationId: 'LOC-0025',
    unlockedNpcIds: ['NPC-0003'],
    skills: base.skills.map((skill) =>
      skill.skillId === 'SKL-0011' || skill.skillId === 'SKL-0008' || skill.skillId === 'SKL-0012'
        ? { ...skill, level: 40, xp: 500_000 }
        : skill,
    ),
    inventory: [
      { itemId: 'ITEM-0074', quantity: 40 },
      { itemId: 'ITEM-0214', quantity: 8 },
      { itemId: 'ITEM-0084', quantity: 30 },
      { itemId: 'ITEM-0100', quantity: 2 },
    ],
  }
}

/** At the Mages quarters with enchantment inputs and an axe to enchant. */
export function arcanaSave(db: GameDatabase): PlayerSave {
  const base = baseSave(db)
  return {
    ...base,
    characterName: 'Mage',
    raceId: 'RACE-0005',
    gold: 10_000,
    currentLocationId: 'LOC-0007',
    unlockedNpcIds: ['NPC-0004'],
    skills: base.skills.map((skill) =>
      skill.skillId === 'SKL-0013' ? { ...skill, level: 40, xp: 900_000 } : skill,
    ),
    inventory: [
      { itemId: 'ITEM-0098', quantity: 2 },
      { itemId: 'ITEM-0011', quantity: 6 },
      { itemId: 'ITEM-0040', quantity: 2 },
      { itemId: 'ITEM-0132', quantity: 1 },
    ],
    equipment: {
      slots: { ...base.equipment.slots, 'SLOT-0001': { itemId: 'ITEM-0102', quantity: 1 } },
    },
  }
}

/**
 * Standing at Rose with QST-0002 active and everything it asks for, plus a
 * completed QST-0001 so repeat turn-ins are covered too.
 */
export function questSave(db: GameDatabase): PlayerSave {
  const base = baseSave(db)
  return {
    ...base,
    characterName: 'Runner',
    gold: 5_000,
    currentLocationId: 'LOC-0023',
    inventory: [
      { itemId: 'ITEM-0038', quantity: 6 },
      { itemId: 'ITEM-0031', quantity: 5 },
      { itemId: 'ITEM-0058', quantity: 12 },
    ],
    quests: [
      { questId: 'QST-0001', status: 'completed', progress: 10, counters: {} },
      { questId: 'QST-0002', status: 'active', progress: 0, counters: {} },
    ],
  }
}

/** In the goblin camp with a weapon, food, and combat XP, ready to trade blows. */
export function combatSave(db: GameDatabase): PlayerSave {
  const base = baseSave(db)
  return {
    ...base,
    characterName: 'Fighter',
    raceId: 'RACE-0003',
    gold: 500,
    currentLocationId: 'LOC-0003',
    currentHp: 700,
    skills: base.skills.map((skill) =>
      skill.skillId === 'SKL-0001' ? { ...skill, level: 20, xp: 40_000 } : skill,
    ),
    inventory: [{ itemId: 'ITEM-0058', quantity: 5 }],
    equipment: {
      slots: {
        ...base.equipment.slots,
        'SLOT-0001': { itemId: 'ITEM-0130', quantity: 1 },
        'SLOT-0011': { itemId: 'ITEM-0059', quantity: 3 },
      },
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
