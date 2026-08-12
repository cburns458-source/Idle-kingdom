import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import type { GameDatabase } from '../../game/data/types'
import { DATABASE_TABLES } from '../../game/data/types'
import type { JsonValue } from '../types'

/** Rows as plain JSON, which is what both clients actually load. */
export type JsonDatabase = Record<string, JsonValue[]>

export const CONTENT_DATABASE_PATH = 'content/data/game-database.json'

let cached: unknown

/** The real shared database, read once. Dart replays read the same file. */
export function contentDatabase(): GameDatabase {
  cached ??= JSON.parse(readFileSync(resolve(process.cwd(), CONTENT_DATABASE_PATH), 'utf8'))
  return cached as GameDatabase
}

/** Rows are read structurally by validation, so plain JSON is the honest input. */
export function asDatabase(db: JsonDatabase): GameDatabase {
  return db as unknown as GameDatabase
}

/**
 * Smallest database that passes validation: every table present, the required
 * config keys, and the starting location. Broken variants mutate a copy.
 */
export function minimalDatabase(): JsonDatabase {
  const db: JsonDatabase = {}
  for (const table of DATABASE_TABLES) db[table] = []

  db.Config = [
    configRow('primary_activity_slots', 1),
    configRow('save_slots', 1),
    configRow('unattended_cap', 43200000),
    configRow('currency_item_id', 'ITEM-0001'),
    configRow('starting_max_hp', 1000),
  ]
  db.Maps = [
    {
      'Map ID': 'MAP-0001',
      'Internal Key': 'main',
      'Display Name': 'Main',
      'Map Type': null,
      'Asset Key': null,
      Status: 'Confirmed',
      'Release Phase': 'Launch',
      Description: null,
    },
  ]
  db.Locations = [location('LOC-0002', 'The Town')]
  db.Items = [item('ITEM-0001', 'Gold Coin')]
  db.Skills = [skill('SKL-0001', 'Woodcutting')]

  return db
}

export function withRows(base: JsonDatabase, table: string, rows: JsonValue[]): JsonDatabase {
  return { ...base, [table]: rows }
}

export function configRow(key: string, value: JsonValue): JsonValue {
  return { Key: key, Value: value, Unit: null, Notes: null }
}

export function location(id: string, name: string, extra: JsonValue = {}): JsonValue {
  return {
    'Location ID': id,
    'Internal Key': id.toLowerCase(),
    'Display Name': name,
    'Map ID': 'MAP-0001',
    'Location Type': null,
    'Parent Location ID': null,
    'Node ID': null,
    Status: 'Confirmed',
    'Release Phase': 'Launch',
    Description: null,
    'Danger / Hostility': null,
    'Background Asset Key': null,
    Notes: null,
    ...(extra as object),
  }
}

export function item(id: string, name: string, extra: JsonValue = {}): JsonValue {
  return {
    'Item ID': id,
    'Internal Key': id.toLowerCase(),
    'Display Name': name,
    Category: null,
    Subtype: null,
    Status: 'Confirmed',
    'Release Phase': 'Launch',
    'Associated Skill ID': null,
    'Equipment Slot ID': null,
    'Base Sell Value': null,
    'Icon Asset Key': null,
    Description: null,
    'Functional / Source Tags': null,
    Notes: null,
    ...(extra as object),
  }
}

export function skill(id: string, name: string, extra: JsonValue = {}): JsonValue {
  return {
    'Skill ID': id,
    'Internal Key': id.toLowerCase(),
    'Display Name': name,
    Category: 'Gathering',
    Description: null,
    Status: 'Confirmed',
    'Release Phase': 'Launch',
    'Rules / Notes': null,
    ...(extra as object),
  }
}

export function action(id: string, skillId: string, extra: JsonValue = {}): JsonValue {
  return {
    'Action ID': id,
    'Internal Key': id.toLowerCase(),
    'Display Name': id,
    Category: 'Gathering',
    'Relevant Skill ID': skillId,
    'Target Type': null,
    'Target ID': null,
    'Proficiency Level': null,
    'Base Duration Seconds': null,
    'XP Reward': null,
    'Guaranteed Gold': null,
    'Drop Chance': null,
    'Reward Table ID': null,
    'Secondary Drop Chance': null,
    'Secondary Reward Table ID': null,
    Status: 'Confirmed',
    'Release Phase': 'Launch',
    Notes: null,
    ...(extra as object),
  }
}

export function activity(id: string, locationId: string, extra: JsonValue = {}): JsonValue {
  return {
    'Activity ID': id,
    'Internal Key': id.toLowerCase(),
    'Contextual Name': null,
    'Location ID': locationId,
    'Pool ID': 'POOL-0001',
    'Pool Internal Key': null,
    Description: null,
    'Danger Warning Combat Level': null,
    Status: 'Confirmed',
    'Release Phase': 'Launch',
    Notes: null,
    ...(extra as object),
  }
}

export function facility(id: string, locationId: string, extra: JsonValue = {}): JsonValue {
  return {
    'Facility ID': id,
    'Internal Key': id.toLowerCase(),
    'Display Name': id,
    'Facility Type': null,
    'Location ID': locationId,
    'Skill ID': null,
    Status: 'Confirmed',
    'Release Phase': 'Launch',
    Description: null,
    Notes: null,
    ...(extra as object),
  }
}

export function npc(id: string, locationId: string, extra: JsonValue = {}): JsonValue {
  return {
    'NPC ID': id,
    'Internal Key': id.toLowerCase(),
    'Display Name': id,
    'Location ID': locationId,
    Role: null,
    Status: 'Confirmed',
    'Release Phase': 'Launch',
    Description: null,
    Notes: null,
    ...(extra as object),
  }
}

export function shop(id: string, locationId: string, extra: JsonValue = {}): JsonValue {
  return {
    'Shop ID': id,
    'Internal Key': id.toLowerCase(),
    'Display Name': id,
    'Location ID': locationId,
    'Shop Type': null,
    Status: 'Confirmed',
    'Release Phase': 'Launch',
    Description: null,
    Notes: null,
    'Entry 1 Item': 'ITEM-0001',
    'Entry 1 Price': 12,
    ...(extra as object),
  }
}

export function poolEntry(id: string, poolId: string, actionId: string): JsonValue {
  return {
    'Pool Entry ID': id,
    'Pool ID': poolId,
    'Action ID': actionId,
    Weight: 1,
    Status: 'Confirmed',
    Notes: null,
  }
}

export function rewardEntry(id: string, tableId: string): JsonValue {
  return {
    'Reward Entry ID': id,
    'Reward Table ID': tableId,
    'Reward Table Name': null,
    Purpose: null,
    'Reward Type': 'Item',
    'Reward ID / Value': 'ITEM-0001',
    Weight: 1,
    'Minimum Quantity': 1,
    'Maximum Quantity': 1,
    'Skill ID': null,
    'XP Amount': null,
    Status: 'Confirmed',
    Notes: null,
  }
}

export function locationSearch(id: string, locationId: string, itemId: string): JsonValue {
  return {
    'Search ID': id,
    'Internal Key': id.toLowerCase(),
    'Location ID': locationId,
    'Display Name': id,
    'Button Label': 'Search',
    'Reward Item ID': itemId,
    'Reward Quantity': 1,
    'Cooldown Hours': 24,
    Status: 'Confirmed',
    'Release Phase': 'Launch',
    Notes: null,
  }
}

export function cosmetic(id: string, itemId: string, slotId: string): JsonValue {
  return {
    'Cosmetic ID': id,
    'Item ID': itemId,
    'Cosmetic Slot ID': slotId,
    'Acquisition Tags': null,
    Status: 'Confirmed',
    'Release Phase': 'Launch',
    Notes: null,
  }
}

export function race(id: string, extra: JsonValue = {}): JsonValue {
  return {
    'Race ID': id,
    'Internal Key': id.toLowerCase(),
    'Display Name': id,
    Description: null,
    'Sort Order': 1,
    'Portrait Asset Key': null,
    'Hostility Immunity Location IDs': null,
    Status: 'Confirmed',
    'Release Phase': 'Launch',
    Notes: null,
    ...(extra as object),
  }
}

export function raceBonus(id: string, raceId: string, extra: JsonValue = {}): JsonValue {
  return {
    'Race Bonus ID': id,
    'Race ID': raceId,
    'Bonus Type': 'gold_gain_percent',
    'Reference ID': null,
    'Bonus Value': 5,
    Status: 'Confirmed',
    Notes: null,
    ...(extra as object),
  }
}

export function raceStartingItem(id: string, raceId: string, itemId: string): JsonValue {
  return {
    'Race Starting Item ID': id,
    'Race ID': raceId,
    'Item ID': itemId,
    Quantity: 1,
    'Sort Order': 1,
    Status: 'Confirmed',
    Notes: null,
  }
}
