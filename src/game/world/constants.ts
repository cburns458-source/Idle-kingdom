/** Travel delay when database Base Duration is null. 0 = instant travel. */
export const DEFAULT_TRAVEL_DURATION_MS = 0

export const MAIN_MAP_ID = 'MAP-0001'
export const CAVE_MAP_ID = 'MAP-0002'
export const CASTLE_MAP_ID = 'MAP-0003'
export const WEST_MAP_ID = 'MAP-0004'
export const EAST_MAP_ID = 'MAP-0005'
export const TOWN_MAP_ID = 'MAP-0006'
export const CITADEL_MAP_ID = 'MAP-0007'
export const FOREST_MAP_ID = 'MAP-0008'
export const DEPTHS_MAP_ID = 'MAP-0009'
export const MOUNTAINS_MAP_ID = 'MAP-0010'

export const CAVE_ENTRANCE_ID = 'LOC-0010'
export const CAVE_MINING_STORE_ID = 'LOC-0012'
export const CASTLE_GATEWAY_ID = 'LOC-0013'
export const CASTLE_COURTYARD_ID = 'LOC-0014'
export const TOWN_GATEWAY_ID = 'LOC-0002'
export const CITADEL_GATEWAY_ID = 'LOC-0027'
export const WEST_HORIZON_ID = 'LOC-0019'
export const EAST_HORIZON_ID = 'LOC-0020'

/** Town district nodes (MAP-0006). */
export const TOWN_KITCHEN_ID = 'LOC-0023'
export const TOWN_GENERAL_STORE_ID = 'LOC-0024'
export const TOWN_FOUNDRY_ID = 'LOC-0025'
export const TOWN_APOTHECARY_ID = 'LOC-0026'
export const TOWN_BANK_ID = 'LOC-0034'

/** Citadel hub nodes (MAP-0007). */
export const CITADEL_PLAZA_ID = 'LOC-0028'
export const CITADEL_MARKET_ID = 'LOC-0029'
export const CITADEL_PROCESSING_ID = 'LOC-0030'
export const CITADEL_GATHERING_ID = 'LOC-0031'
export const CITADEL_COMBAT_ID = 'LOC-0032'
export const GUILD_HALL_LOCATION_ID = 'LOC-0033'
export const CITADEL_BANK_ID = 'LOC-0035'

/** Ancient Forest woodland (MAP-0008). */
export const FOREST_GATEWAY_ID = 'LOC-0039'
export const FOREST_PATH_ID = 'LOC-0040'
export const OLD_ENT_GROVE_ID = 'LOC-0018'
export const STARLIGHT_GLADE_ID = 'LOC-0044'
export const SMALL_CLEARING_ID = 'LOC-0050'
export const MIRROR_LAKE_ID = 'LOC-0051'
export const THROUGH_THE_THICKET_QUEST_ID = 'QST-0010'
export const FOREST_PATH_VINES_ACTIVITY_ID = 'ACT-0048'
export const SMALL_CLEARING_VINES_ACTIVITY_ID = 'ACT-0077'
export const STARLIGHT_VINES_ACTIVITY_ID = 'ACT-0078'
export const MIRROR_LAKE_VINES_ACTIVITY_ID = 'ACT-0079'
export const OLD_ENT_GROVE_VINES_ACTIVITY_ID = 'ACT-0082'
export const FOREST_PATH_VINES_STEP_ID = 'QSTP-0025'
export const SMALL_CLEARING_VINES_STEP_ID = 'QSTP-0027'
export const STARLIGHT_VINES_STEP_ID = 'QSTP-0028'
export const MIRROR_LAKE_VINES_STEP_ID = 'QSTP-0029'
export const OLD_ENT_GROVE_VINES_STEP_ID = 'QSTP-0036'

export interface ThicketVineActivitySpec {
  locationId: string
  stepId: string
  persistAfterQuest: boolean
}

/** Chop vines nodes for Through the Thicket. Path stays after completion; the rest do not. */
export const THICKET_VINE_ACTIVITIES: Record<string, ThicketVineActivitySpec> = {
  [FOREST_PATH_VINES_ACTIVITY_ID]: {
    locationId: FOREST_PATH_ID,
    stepId: FOREST_PATH_VINES_STEP_ID,
    persistAfterQuest: true,
  },
  [SMALL_CLEARING_VINES_ACTIVITY_ID]: {
    locationId: SMALL_CLEARING_ID,
    stepId: SMALL_CLEARING_VINES_STEP_ID,
    persistAfterQuest: false,
  },
  [STARLIGHT_VINES_ACTIVITY_ID]: {
    locationId: STARLIGHT_GLADE_ID,
    stepId: STARLIGHT_VINES_STEP_ID,
    persistAfterQuest: false,
  },
  [MIRROR_LAKE_VINES_ACTIVITY_ID]: {
    locationId: MIRROR_LAKE_ID,
    stepId: MIRROR_LAKE_VINES_STEP_ID,
    persistAfterQuest: false,
  },
  [OLD_ENT_GROVE_VINES_ACTIVITY_ID]: {
    locationId: OLD_ENT_GROVE_ID,
    stepId: OLD_ENT_GROVE_VINES_STEP_ID,
    persistAfterQuest: false,
  },
}

export function leftVinesFlag(locationId: string): string {
  return `leftVines:${locationId}`
}

/** Inner forest nodes granted when Through the Thicket is completed. */
export const THICKET_COMPLETION_LOCATION_IDS = [
  SMALL_CLEARING_ID,
  STARLIGHT_GLADE_ID,
  MIRROR_LAKE_ID,
  OLD_ENT_GROVE_ID,
] as const

/** The Depths underwater (MAP-0009). */
export const SUNKEN_APPROACH_ID = 'LOC-0041'
export const THE_DEPTHS_ID = 'LOC-0042'
export const THE_SHALLOWS_ID = 'LOC-0043'

/** Mountains range (MAP-0010). */
export const MOUNTAINS_GATEWAY_ID = 'LOC-0006'
export const THE_SLOPES_ID = 'LOC-0046'
export const THE_PEAK_ID = 'LOC-0047'
export const BADLANDS_ID = 'LOC-0048'
export const GIANT_CAMP_ID = 'LOC-0049'

export function isFutureHorizonLocation(locationId: string): boolean {
  return locationId === WEST_HORIZON_ID || locationId === EAST_HORIZON_ID
}

export function adjacentMapForHorizon(locationId: string): string | null {
  if (locationId === WEST_HORIZON_ID) return WEST_MAP_ID
  if (locationId === EAST_HORIZON_ID) return EAST_MAP_ID
  return null
}

export function isFutureRegionMapId(mapId: string | null | undefined): boolean {
  return mapId === WEST_MAP_ID || mapId === EAST_MAP_ID
}
