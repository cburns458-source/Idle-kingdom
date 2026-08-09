/** Stable runtime asset paths keyed by database IDs / internal keys. */

export const MAP_ASSET_PATHS: Record<string, string> = {
  'MAP-0001': '/assets/maps/map_idale_main.png',
  'MAP-0002': '/assets/maps/map_mountain_caves.png',
  'MAP-0003': '/assets/maps/map_castle_grounds.png',
}

export const LOCATION_ASSET_PATHS: Record<string, string> = {
  'LOC-0001': '/assets/locations/loc_farm.png',
  'LOC-0002': '/assets/locations/loc_town.png',
  'LOC-0003': '/assets/locations/loc_goblin_camp.png',
  'LOC-0004': '/assets/locations/loc_river_coast_dock.png',
  'LOC-0005': '/assets/locations/loc_copper_mine.png',
  'LOC-0006': '/assets/locations/loc_mountains.png',
  'LOC-0007': '/assets/locations/loc_wizards_tower.png',
  'LOC-0008': '/assets/locations/loc_kingswoods.png',
  'LOC-0009': '/assets/locations/loc_meadow.png',
  'LOC-0010': '/assets/locations/loc_cave_entrance.png',
  'LOC-0011': '/assets/locations/loc_deep_mines.png',
  'LOC-0012': '/assets/locations/loc_dwarven_mining_store.png',
  'LOC-0013': '/assets/locations/loc_castle.png',
  'LOC-0014': '/assets/locations/loc_castle_courtyard.png',
  'LOC-0015': '/assets/locations/loc_castle_main_hall.png',
  'LOC-0016': '/assets/locations/loc_kings_quarters.png',
  'LOC-0017': '/assets/locations/loc_castle_barracks.png',
}

export function mapAssetPath(mapId: string): string {
  return MAP_ASSET_PATHS[mapId] ?? '/assets/maps/map_idale_main.png'
}

export function locationAssetPath(locationId: string): string {
  return LOCATION_ASSET_PATHS[locationId] ?? '/assets/locations/loc_town.png'
}
