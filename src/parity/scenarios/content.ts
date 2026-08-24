import { prepareDatabase } from '../../game/data/loadDatabase'
import {
  assertGameDatabaseShape,
  buildIndexes,
  countNeedsData,
  filterLaunchContent,
  validateDatabase,
} from '../../game/data/validate'
import { DATABASE_TABLES, type DatabaseIndexes, type GameDatabase } from '../../game/data/types'
import { scenario, type JsonValue, type ParityScenario } from '../types'
import {
  action,
  activity,
  asDatabase,
  configRow,
  contentDatabase,
  cosmetic,
  facility,
  item,
  location,
  locationSearch,
  minimalDatabase,
  npc,
  poolEntry,
  race,
  raceBonus,
  raceStartingItem,
  rewardEntry,
  shop,
  skill,
  withRows,
  type JsonDatabase,
} from './contentDatabase'

/** Marks a scenario as running against the real shared database. */
const CONTENT_SOURCE: JsonValue = { source: 'content' }

function inlineSource(database: JsonDatabase): JsonValue {
  return { source: 'inline', database: database as unknown as JsonValue }
}

function issuesOf(db: GameDatabase): JsonValue {
  return { issues: validateDatabase(db) as unknown as JsonValue }
}

function tableCounts(db: GameDatabase): JsonValue {
  const counts: Record<string, number> = {}
  for (const table of DATABASE_TABLES) {
    counts[table] = (db[table] as unknown[]).length
  }
  return counts
}

function idsOf(rows: unknown[], idField: string): string[] {
  return rows.map((row) => String((row as Record<string, unknown>)[idField] ?? ''))
}

function groupSummary(
  group: Map<string, unknown[]>,
  idField: string,
): Record<string, string[]> {
  const summary: Record<string, string[]> = {}
  for (const [key, rows] of group) summary[key] = idsOf(rows, idField)
  return summary
}

/** Full index contents, for the small synthetic databases. */
function indexSummary(indexes: DatabaseIndexes): JsonValue {
  return {
    configByKey: [...indexes.configByKey.keys()],
    skillsById: [...indexes.skillsById.keys()],
    skillDisplayNames: [...indexes.skillsById.values()].map((row) => row['Display Name']),
    locationsById: [...indexes.locationsById.keys()],
    itemsById: [...indexes.itemsById.keys()],
    mapsById: [...indexes.mapsById.keys()],
    activitiesById: [...indexes.activitiesById.keys()],
    actionsById: [...indexes.actionsById.keys()],
    facilitiesByLocationId: groupSummary(indexes.facilitiesByLocationId, 'Facility ID'),
    activitiesByLocationId: groupSummary(indexes.activitiesByLocationId, 'Activity ID'),
    npcsByLocationId: groupSummary(indexes.npcsByLocationId, 'NPC ID'),
    shopsByLocationId: groupSummary(indexes.shopsByLocationId, 'Shop ID'),
    poolEntriesByPoolId: groupSummary(indexes.poolEntriesByPoolId, 'Pool Entry ID'),
    rewardEntriesByTableId: groupSummary(indexes.rewardEntriesByTableId, 'Reward Entry ID'),
    locationSearchesByLocationId: groupSummary(
      indexes.locationSearchesByLocationId,
      'Search ID',
    ),
    byTableIdCounts: Object.fromEntries(
      [...indexes.byTableId].map(([table, map]) => [table, map.size]),
    ),
  } as unknown as JsonValue
}

/** Cardinality plus the ends of each key sequence, for the real database. */
function compactIndexSummary(indexes: DatabaseIndexes): JsonValue {
  const ends = (keys: string[]): JsonValue => ({
    count: keys.length,
    first: keys.slice(0, 3),
    last: keys.slice(-3),
  })
  const groupEnds = (group: Map<string, unknown[]>): JsonValue => ({
    count: group.size,
    first: [...group.keys()].slice(0, 3),
    last: [...group.keys()].slice(-3),
    sizes: Object.fromEntries([...group].map(([key, rows]) => [key, rows.length])),
  })

  return {
    configByKey: ends([...indexes.configByKey.keys()]),
    skillsById: ends([...indexes.skillsById.keys()]),
    locationsById: ends([...indexes.locationsById.keys()]),
    itemsById: ends([...indexes.itemsById.keys()]),
    mapsById: ends([...indexes.mapsById.keys()]),
    activitiesById: ends([...indexes.activitiesById.keys()]),
    actionsById: ends([...indexes.actionsById.keys()]),
    facilitiesByLocationId: groupEnds(indexes.facilitiesByLocationId),
    activitiesByLocationId: groupEnds(indexes.activitiesByLocationId),
    npcsByLocationId: groupEnds(indexes.npcsByLocationId),
    shopsByLocationId: groupEnds(indexes.shopsByLocationId),
    poolEntriesByPoolId: groupEnds(indexes.poolEntriesByPoolId),
    rewardEntriesByTableId: groupEnds(indexes.rewardEntriesByTableId),
    locationSearchesByLocationId: groupEnds(indexes.locationSearchesByLocationId),
    byTableIdCounts: Object.fromEntries(
      [...indexes.byTableId].map(([table, map]) => [table, map.size]),
    ),
  } as unknown as JsonValue
}

function shapeError(raw: unknown): JsonValue {
  try {
    assertGameDatabaseShape(raw)
    return { error: null }
  } catch (error) {
    return { error: (error as Error).message }
  }
}

function prepareResult(raw: unknown): JsonValue {
  try {
    const loaded = prepareDatabase(raw)
    return {
      ok: true,
      needsDataCount: loaded.needsDataCount,
      issueCount: loaded.issues.length,
      launchCounts: tableCounts(loaded.launch),
      sourceCounts: tableCounts(loaded.source),
    }
  } catch (error) {
    return { ok: false, error: (error as Error).message }
  }
}

/** Databases that must produce validation errors, one per validator branch. */
function brokenDatabases(): Array<[string, JsonDatabase]> {
  const base = minimalDatabase()

  const duplicateIds = withRows(
    withRows(base, 'Skills', [
      skill('SKL-0001', 'First'),
      skill('SKL-0001', 'Second'),
      skill('SKL-0002', 'Third'),
    ]),
    'Items',
    [item('ITEM-0001', 'Gold'), item('ITEM-0001', 'Gold Again')],
  )

  const missingIdFields = withRows(base, 'Skills', [
    skill('SKL-0001', 'Fine'),
    { ...(skill('', 'Empty') as object) } as JsonValue,
    { 'Display Name': 'No id column at all' },
  ])

  const locationRefs = withRows(base, 'Locations', [
    location('LOC-0002', 'The Town'),
    location('LOC-0003', 'Bad Map', { 'Map ID': 'MAP-9999' }),
    location('LOC-0004', 'Bad Parent', { 'Parent Location ID': 'LOC-9999' }),
    location('LOC-0005', 'Empty Map', { 'Map ID': '' }),
  ])

  const activityRefs = withRows(base, 'Activities', [
    activity('ACT-0001', 'LOC-0002'),
    activity('ACT-0002', 'LOC-9999'),
  ])

  const poolEntryRefs = withRows(
    withRows(base, 'Actions', [action('ACN-0001', 'SKL-0001')]),
    'PoolEntries',
    [poolEntry('PEN-0001', 'POOL-0001', 'ACN-0001'), poolEntry('PEN-0002', 'POOL-0001', 'ACN-9999')],
  )

  const actionSkillRefs = withRows(base, 'Actions', [
    action('ACN-0001', 'SKL-0001'),
    action('ACN-0002', 'SKL-9999'),
  ])

  const cosmeticRefs = withRows(
    withRows(base, 'CosmeticSlots', [
      {
        'Cosmetic Slot ID': 'CSLOT-0001',
        'Internal Key': 'outfit',
        'Display Name': 'Outfit',
        'Slot Group': null,
        Status: 'Confirmed',
        'Release Phase': 'Launch',
        Notes: null,
      },
    ]),
    'Cosmetics',
    [
      cosmetic('COS-0001', 'ITEM-0001', 'CSLOT-0001'),
      cosmetic('COS-0002', 'ITEM-9999', 'CSLOT-9999'),
    ],
  )

  const searchRefs = withRows(base, 'LocationSearches', [
    locationSearch('SRCH-0001', 'LOC-0002', 'ITEM-0001'),
    locationSearch('SRCH-0002', 'LOC-9999', 'ITEM-9999'),
  ])

  const raceRefs = withRows(
    withRows(withRows(base, 'Races', [race('RACE-0001')]), 'RaceBonuses', [
      raceBonus('RB-0001', 'RACE-0001'),
      raceBonus('RB-0002', 'RACE-9999'),
      raceBonus('RB-0003', 'RACE-0001', {
        'Bonus Type': 'skill_drop_chance_percent',
        'Reference ID': 'SKL-9999',
      }),
      raceBonus('RB-0004', 'RACE-0001', {
        'Bonus Type': 'skill_drop_chance_percent',
        'Reference ID': 'SKL-0001',
      }),
      // Non-skill bonus types ignore a dangling reference.
      raceBonus('RB-0005', 'RACE-0001', {
        'Bonus Type': 'gold_gain_percent',
        'Reference ID': 'SKL-9999',
      }),
    ]),
    'RaceStartingItems',
    [
      raceStartingItem('RSI-0001', 'RACE-0001', 'ITEM-0001'),
      raceStartingItem('RSI-0002', 'RACE-9999', 'ITEM-9999'),
    ],
  )

  const hostilityImmunity = withRows(base, 'Races', [
    race('RACE-0001', { 'Hostility Immunity Location IDs': ' LOC-0002 ; LOC-9999 ;; ' }),
    race('RACE-0002', { 'Hostility Immunity Location IDs': '   ' }),
    race('RACE-0003', { 'Hostility Immunity Location IDs': 'LOC-8888;LOC-7777' }),
  ])

  const missingConfig = withRows(base, 'Config', [
    configRow('save_slots', 1),
    configRow('currency_item_id', 'ITEM-0001'),
  ])

  const missingStartingLocation = withRows(base, 'Locations', [location('LOC-0001', 'Farm')])

  // Combines categories so cross-category issue ordering is locked down too.
  const everythingBroken = withRows(
    withRows(missingConfig, 'Locations', [
      location('LOC-0003', 'Bad Map', { 'Map ID': 'MAP-9999' }),
    ]),
    'Actions',
    [action('ACN-0001', 'SKL-9999'), action('ACN-0001', 'SKL-9999')],
  )

  return [
    ['duplicate-ids', duplicateIds],
    ['missing-id-fields', missingIdFields],
    ['location-refs', locationRefs],
    ['activity-location-refs', activityRefs],
    ['pool-entry-action-refs', poolEntryRefs],
    ['action-skill-refs', actionSkillRefs],
    ['cosmetic-refs', cosmeticRefs],
    ['location-search-refs', searchRefs],
    ['race-refs', raceRefs],
    ['hostility-immunity-refs', hostilityImmunity],
    ['missing-config-keys', missingConfig],
    ['missing-starting-location', missingStartingLocation],
    ['everything-broken', everythingBroken],
  ]
}

function launchFilterDatabase(): JsonDatabase {
  const base = minimalDatabase()
  return withRows(
    withRows(
      withRows(base, 'Skills', [
        skill('SKL-0001', 'Launch'),
        skill('SKL-0002', 'Expansion', { 'Release Phase': 'Expansion' }),
        // A row without the column at all stays visible.
        { 'Skill ID': 'SKL-0003', 'Display Name': 'No phase column' },
      ]),
      'RaceBonuses',
      [
        raceBonus('RB-0001', 'RACE-0001'),
        raceBonus('RB-0002', 'RACE-0001', { 'Release Phase': 'Expansion' }),
      ],
    ),
    'Races',
    [race('RACE-0001'), race('RACE-0002', { 'Release Phase': 'Expansion' })],
  )
}

function indexDatabase(): JsonDatabase {
  const base = minimalDatabase()
  return {
    ...base,
    Skills: [skill('SKL-0001', 'First'), skill('SKL-0001', 'Duplicate Wins')],
    Locations: [location('LOC-0002', 'The Town'), location('LOC-0003', 'Farm')],
    Actions: [action('ACN-0001', 'SKL-0001'), action('ACN-0002', 'SKL-0001')],
    Activities: [
      activity('ACT-0002', 'LOC-0003'),
      activity('ACT-0001', 'LOC-0002'),
      activity('ACT-0003', 'LOC-0003'),
    ],
    Facilities: [facility('FAC-0001', 'LOC-0002'), facility('FAC-0002', 'LOC-0002')],
    NPCs: [npc('NPC-0001', 'LOC-0003')],
    Shops: [shop('SHP-0001', 'LOC-0002'), shop('SHP-0002', 'LOC-0003')],
    PoolEntries: [
      poolEntry('PEN-0002', 'POOL-0002', 'ACN-0001'),
      poolEntry('PEN-0001', 'POOL-0001', 'ACN-0001'),
      poolEntry('PEN-0003', 'POOL-0002', 'ACN-0002'),
    ],
    RewardEntries: [rewardEntry('REW-0001', 'RWD-0001'), rewardEntry('REW-0002', 'RWD-0001')],
    LocationSearches: [
      locationSearch('SRCH-0001', 'LOC-0003', 'ITEM-0001'),
      locationSearch('SRCH-0002', 'LOC-0003', 'ITEM-0001'),
    ],
  }
}

export const contentScenarios: ParityScenario[] = [
  scenario('content/validate', 'real-database', CONTENT_SOURCE, () =>
    issuesOf(contentDatabase()),
  ),
  scenario('content/prepare', 'real-database', CONTENT_SOURCE, () =>
    prepareResult(contentDatabase()),
  ),
  scenario('content/needs-data', 'real-database', CONTENT_SOURCE, () => ({
    needsDataCount: countNeedsData(contentDatabase()),
  })),
  scenario('content/launch', 'real-database', CONTENT_SOURCE, () =>
    tableCounts(filterLaunchContent(contentDatabase())),
  ),
  scenario('content/indexes', 'real-database-source', CONTENT_SOURCE, () =>
    compactIndexSummary(buildIndexes(contentDatabase())),
  ),
  scenario('content/indexes', 'real-database-launch', CONTENT_SOURCE, () =>
    compactIndexSummary(buildIndexes(filterLaunchContent(contentDatabase()))),
  ),

  scenario('content/validate', 'minimal-database', inlineSource(minimalDatabase()), () =>
    issuesOf(asDatabase(minimalDatabase())),
  ),
  ...brokenDatabases().map(([name, database]) =>
    scenario(`content/validate`, name, inlineSource(database), () =>
      issuesOf(asDatabase(database)),
    ),
  ),
  scenario('content/prepare', 'rejects-broken-database', inlineSource(brokenDatabases()[12]![1]), () =>
    prepareResult(brokenDatabases()[12]![1]),
  ),

  scenario('content/shape', 'root-not-object', { source: 'raw', value: 7 }, () => shapeError(7)),
  scenario('content/shape', 'root-array', { source: 'raw', value: [] }, () => shapeError([])),
  scenario(
    'content/shape',
    'missing-table',
    { source: 'raw', value: { Config: [] } },
    () => shapeError({ Config: [] }),
  ),
  scenario(
    'content/shape',
    'table-not-array',
    inlineSource({ ...minimalDatabase(), Skills: 'nope' as unknown as JsonValue[] }),
    () => shapeError({ ...minimalDatabase(), Skills: 'nope' }),
  ),

  scenario('content/launch', 'phase-filtering', inlineSource(launchFilterDatabase()), () => {
    const filtered = filterLaunchContent(asDatabase(launchFilterDatabase()))
    return {
      skills: idsOf(filtered.Skills, 'Skill ID'),
      races: idsOf(filtered.Races, 'Race ID'),
      raceBonuses: idsOf(filtered.RaceBonuses, 'Race Bonus ID'),
      counts: tableCounts(filtered),
    } as unknown as JsonValue
  }),

  scenario('content/indexes', 'synthetic-database', inlineSource(indexDatabase()), () =>
    indexSummary(buildIndexes(asDatabase(indexDatabase()))),
  ),
  scenario('content/validate', 'index-database', inlineSource(indexDatabase()), () =>
    issuesOf(asDatabase(indexDatabase())),
  ),
]
