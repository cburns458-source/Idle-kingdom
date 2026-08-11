import {
  DATABASE_TABLES,
  type ActivityRow,
  type DatabaseIndexes,
  type FacilityRow,
  type GameDatabase,
  type NpcRow,
  type PoolEntryRow,
  type RewardEntryRow,
  type ShopRow,
  type ValidationIssue,
} from './types'

const TABLE_ID_FIELDS: Record<string, string> = {
  Skills: 'Skill ID',
  EquipmentSlots: 'Slot ID',
  Items: 'Item ID',
  Equipment: 'Equipment ID',
  Statistics: 'Statistic ID',
  Enchantments: 'Enchantment ID',
  Maps: 'Map ID',
  Locations: 'Location ID',
  TravelConnections: 'Connection ID',
  Facilities: 'Facility ID',
  Activities: 'Activity ID',
  PoolEntries: 'Pool Entry ID',
  Actions: 'Action ID',
  Requirements: 'Requirement ID',
  Enemies: 'Enemy ID',
  RewardEntries: 'Reward Entry ID',
  Recipes: 'Recipe ID',
  Projects: 'Project ID',
  NPCs: 'NPC ID',
  Shops: 'Shop ID',
  Quests: 'Quest ID',
  Achievements: 'Achievement ID',
  CosmeticSlots: 'Cosmetic Slot ID',
  Cosmetics: 'Cosmetic ID',
  AppearanceOptions: 'Appearance Option ID',
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function groupByLocationId<T extends { 'Location ID': string }>(rows: T[]): Map<string, T[]> {
  const map = new Map<string, T[]>()
  for (const row of rows) {
    const list = map.get(row['Location ID']) ?? []
    list.push(row)
    map.set(row['Location ID'], list)
  }
  return map
}

function groupByKey<T>(rows: T[], keyFn: (row: T) => string): Map<string, T[]> {
  const map = new Map<string, T[]>()
  for (const row of rows) {
    const key = keyFn(row)
    const list = map.get(key) ?? []
    list.push(row)
    map.set(key, list)
  }
  return map
}

export function assertGameDatabaseShape(raw: unknown): asserts raw is GameDatabase {
  if (!isRecord(raw)) {
    throw new Error('Database root must be an object')
  }
  for (const table of DATABASE_TABLES) {
    if (!(table in raw)) {
      throw new Error(`Database missing required table: ${table}`)
    }
    if (!Array.isArray(raw[table])) {
      throw new Error(`Database table must be an array: ${table}`)
    }
  }
}

export function buildIndexes(db: GameDatabase): DatabaseIndexes {
  const byTableId = new Map<string, Map<string, Record<string, unknown>>>()
  const configByKey = new Map(db.Config.map((row) => [row.Key, row]))
  const skillsById = new Map(db.Skills.map((row) => [row['Skill ID'], row]))
  const locationsById = new Map(db.Locations.map((row) => [row['Location ID'], row]))
  const itemsById = new Map(db.Items.map((row) => [row['Item ID'], row]))
  const mapsById = new Map(db.Maps.map((row) => [row['Map ID'], row]))
  const activitiesById = new Map(db.Activities.map((row) => [row['Activity ID'], row]))
  const actionsById = new Map(db.Actions.map((row) => [row['Action ID'], row]))

  for (const [table, idField] of Object.entries(TABLE_ID_FIELDS)) {
    const map = new Map<string, Record<string, unknown>>()
    const rows = db[table as keyof GameDatabase] as Record<string, unknown>[]
    for (const row of rows) {
      const id = row[idField]
      if (typeof id === 'string' && id.length > 0) {
        map.set(id, row)
      }
    }
    byTableId.set(table, map)
  }

  return {
    byTableId,
    configByKey,
    skillsById,
    locationsById,
    itemsById,
    mapsById,
    activitiesById,
    actionsById,
    facilitiesByLocationId: groupByLocationId(db.Facilities),
    activitiesByLocationId: groupByLocationId(db.Activities),
    npcsByLocationId: groupByLocationId(db.NPCs),
    shopsByLocationId: groupByLocationId(db.Shops),
    poolEntriesByPoolId: groupByKey(db.PoolEntries as PoolEntryRow[], (row) => row['Pool ID']),
    rewardEntriesByTableId: groupByKey(
      db.RewardEntries as RewardEntryRow[],
      (row) => row['Reward Table ID'],
    ),
  }
}

export function lookupById(
  indexes: DatabaseIndexes,
  table: string,
  id: string,
): Record<string, unknown> | undefined {
  return indexes.byTableId.get(table)?.get(id)
}

export function validateDatabase(db: GameDatabase): ValidationIssue[] {
  const issues: ValidationIssue[] = []
  const indexes = buildIndexes(db)

  for (const [table, idField] of Object.entries(TABLE_ID_FIELDS)) {
    const rows = db[table as keyof GameDatabase] as Record<string, unknown>[]
    const seen = new Set<string>()
    for (const row of rows) {
      const id = row[idField]
      if (typeof id !== 'string' || id.length === 0) {
        issues.push({
          severity: 'error',
          table,
          message: `Missing ${idField}`,
        })
        continue
      }
      if (seen.has(id)) {
        issues.push({
          severity: 'error',
          table,
          id,
          message: `Duplicate ${idField}: ${id}`,
        })
      }
      seen.add(id)
    }
  }

  for (const location of db.Locations) {
    const mapId = location['Map ID']
    if (mapId && !lookupById(indexes, 'Maps', mapId)) {
      issues.push({
        severity: 'error',
        table: 'Locations',
        id: location['Location ID'],
        message: `Missing Map ID reference: ${mapId}`,
      })
    }
    const parentId = location['Parent Location ID']
    if (parentId && !indexes.locationsById.has(parentId)) {
      issues.push({
        severity: 'error',
        table: 'Locations',
        id: location['Location ID'],
        message: `Missing Parent Location ID reference: ${parentId}`,
      })
    }
  }

  for (const activity of db.Activities) {
    const locationId = activity['Location ID']
    if (typeof locationId === 'string' && !indexes.locationsById.has(locationId)) {
      issues.push({
        severity: 'error',
        table: 'Activities',
        id: activity['Activity ID'],
        message: `Missing Location ID reference: ${locationId}`,
      })
    }
  }

  for (const entry of db.PoolEntries) {
    const actionId = entry['Action ID']
    if (typeof actionId === 'string' && !lookupById(indexes, 'Actions', actionId)) {
      issues.push({
        severity: 'error',
        table: 'PoolEntries',
        id: String(entry['Pool Entry ID'] ?? ''),
        message: `Missing Action ID reference: ${actionId}`,
      })
    }
  }

  for (const action of db.Actions) {
    const skillId = action['Relevant Skill ID']
    if (typeof skillId === 'string' && !indexes.skillsById.has(skillId)) {
      issues.push({
        severity: 'error',
        table: 'Actions',
        id: String(action['Action ID'] ?? ''),
        message: `Missing Relevant Skill ID reference: ${skillId}`,
      })
    }
  }

  for (const cosmetic of db.Cosmetics) {
    const itemId = cosmetic['Item ID']
    if (typeof itemId === 'string' && !indexes.itemsById.has(itemId)) {
      issues.push({
        severity: 'error',
        table: 'Cosmetics',
        id: cosmetic['Cosmetic ID'],
        message: `Missing Item ID reference: ${itemId}`,
      })
    }
    const slotId = cosmetic['Cosmetic Slot ID']
    if (typeof slotId === 'string' && !lookupById(indexes, 'CosmeticSlots', slotId)) {
      issues.push({
        severity: 'error',
        table: 'Cosmetics',
        id: cosmetic['Cosmetic ID'],
        message: `Missing Cosmetic Slot ID reference: ${slotId}`,
      })
    }
  }

  const requiredConfig = [
    'primary_activity_slots',
    'save_slots',
    'unattended_cap',
    'currency_item_id',
    'starting_max_hp',
  ]
  for (const key of requiredConfig) {
    if (!indexes.configByKey.has(key)) {
      issues.push({
        severity: 'error',
        table: 'Config',
        message: `Missing required config key: ${key}`,
      })
    }
  }

  if (!indexes.locationsById.has('LOC-0002')) {
    issues.push({
      severity: 'error',
      table: 'Locations',
      id: 'LOC-0002',
      message: 'Starting location The Town (LOC-0002) is missing',
    })
  }

  return issues
}

function hasLaunchPhase(row: object): boolean {
  if (!('Release Phase' in row)) return true
  return (row as { 'Release Phase'?: unknown })['Release Phase'] === 'Launch'
}

/** Keep source rows intact; expose Launch-eligible views for runtime. */
export function filterLaunchContent(db: GameDatabase): GameDatabase {
  return {
    ...db,
    Skills: db.Skills.filter(hasLaunchPhase),
    Items: db.Items.filter(hasLaunchPhase),
    Statistics: db.Statistics.filter(hasLaunchPhase),
    Enchantments: db.Enchantments.filter(hasLaunchPhase),
    Maps: db.Maps.filter(hasLaunchPhase),
    Locations: db.Locations.filter(hasLaunchPhase),
    TravelConnections: db.TravelConnections.filter(hasLaunchPhase),
    Facilities: db.Facilities.filter(hasLaunchPhase) as FacilityRow[],
    Activities: db.Activities.filter(hasLaunchPhase) as ActivityRow[],
    Actions: db.Actions.filter(hasLaunchPhase),
    Enemies: db.Enemies.filter(hasLaunchPhase),
    Recipes: db.Recipes.filter(hasLaunchPhase),
    Projects: db.Projects.filter(hasLaunchPhase),
    NPCs: db.NPCs.filter(hasLaunchPhase) as NpcRow[],
    Shops: db.Shops.filter(hasLaunchPhase) as ShopRow[],
    Quests: db.Quests.filter(hasLaunchPhase),
    Achievements: db.Achievements.filter(hasLaunchPhase),
    CosmeticSlots: db.CosmeticSlots.filter(hasLaunchPhase),
    Cosmetics: db.Cosmetics.filter(hasLaunchPhase),
    AppearanceOptions: db.AppearanceOptions.filter(hasLaunchPhase),
  }
}

export function countNeedsData(db: GameDatabase): number {
  let count = 0
  for (const table of DATABASE_TABLES) {
    const rows = db[table] as Record<string, unknown>[]
    for (const row of rows) {
      if (row.Status === 'Needs Data') count += 1
    }
  }
  return count
}
