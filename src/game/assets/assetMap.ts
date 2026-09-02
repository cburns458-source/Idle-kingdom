import { withAssetVersion } from './cacheBust'

/** Stable runtime asset paths keyed by database IDs / internal keys. */

export const MAP_ASSET_PATHS: Record<string, string> = {
  'MAP-0001': '/assets/maps/map_idale_main.webp',
  'MAP-0002': '/assets/maps/map_mountain_caves.webp',
  'MAP-0003': '/assets/maps/map_castle_grounds.webp',
  'MAP-0004': '/assets/maps/map_idale_west.webp',
  'MAP-0005': '/assets/maps/map_idale_east.webp',
  'MAP-0006': '/assets/maps/map_town.webp',
  'MAP-0007': '/assets/maps/map_citadel.webp',
  'MAP-0008': '/assets/maps/map_ancient_forest.webp',
  'MAP-0009': '/assets/maps/map_the_depths.webp',
}

export const LOCATION_ASSET_PATHS: Record<string, string> = {
  'LOC-0001': '/assets/locations/loc_farm.webp',
  'LOC-0002': '/assets/locations/loc_town.webp',
  'LOC-0003': '/assets/locations/loc_goblin_camp.webp',
  'LOC-0004': '/assets/locations/loc_river_coast_dock.webp',
  'LOC-0005': '/assets/locations/loc_copper_mine.webp',
  'LOC-0006': '/assets/locations/loc_mountains.webp',
  'LOC-0007': '/assets/locations/loc_wizards_tower.webp',
  'LOC-0008': '/assets/locations/loc_kingswoods.webp',
  'LOC-0009': '/assets/locations/loc_meadow.webp',
  'LOC-0010': '/assets/locations/loc_cave_entrance.webp',
  'LOC-0011': '/assets/locations/loc_deep_mines.webp',
  'LOC-0012': '/assets/locations/loc_dwarven_mining_store.webp',
  'LOC-0013': '/assets/locations/loc_castle.webp',
  'LOC-0014': '/assets/locations/loc_castle_courtyard.webp',
  'LOC-0015': '/assets/locations/loc_castle_main_hall.webp',
  'LOC-0016': '/assets/locations/loc_kings_quarters.webp',
  'LOC-0017': '/assets/locations/loc_castle_barracks.webp',
  'LOC-0018': '/assets/locations/loc_ancient_forest.webp',
  'LOC-0039': '/assets/locations/loc_forest_gate.webp',
  'LOC-0040': '/assets/locations/loc_forest_path.webp',
  'LOC-0041': '/assets/locations/loc_sunken_approach.webp',
  'LOC-0042': '/assets/locations/loc_the_depths.webp',
  'LOC-0043': '/assets/locations/loc_the_shallows.webp',
  'LOC-0044': '/assets/locations/loc_starlight_glade.webp',
  'LOC-0021': '/assets/locations/loc_queens_quarters.webp',
  'LOC-0022': '/assets/locations/loc_abandoned_mineshaft.webp',
  'LOC-0038': '/assets/locations/loc_town_foundry.webp',
  'LOC-0023': '/assets/locations/loc_town_kitchen.webp',
  'LOC-0024': '/assets/locations/loc_town_general_store.webp',
  'LOC-0025': '/assets/locations/loc_town_foundry.webp',
  'LOC-0026': '/assets/locations/loc_town_apothecary.webp',
  'LOC-0027': '/assets/locations/loc_citadel_gateway.webp',
  'LOC-0028': '/assets/locations/loc_citadel_plaza.webp',
  'LOC-0029': '/assets/locations/loc_citadel_market.webp',
  'LOC-0030': '/assets/locations/loc_citadel_processing.webp',
  'LOC-0031': '/assets/locations/loc_citadel_gathering.webp',
  'LOC-0032': '/assets/locations/loc_citadel_combat.webp',
  'LOC-0033': '/assets/locations/loc_guild_hall.webp',
  'LOC-0034': '/assets/locations/loc_town_bank.webp',
  'LOC-0035': '/assets/locations/loc_citadel_bank.webp',
  'LOC-0036': '/assets/locations/loc_temple.webp',
  'LOC-0037': '/assets/locations/loc_castle_crypt.webp',
}

export function mapAssetPath(mapId: string): string {
  return withAssetVersion(MAP_ASSET_PATHS[mapId] ?? '/assets/maps/map_idale_main.webp')
}

export function locationAssetPath(locationId: string): string {
  return withAssetVersion(LOCATION_ASSET_PATHS[locationId] ?? '/assets/locations/loc_town.webp')
}

export function uiMapAssetPath(): string {
  return withAssetVersion('/assets/icons/ui/ui_map.webp')
}

export function uiNearbyAssetPath(): string {
  return withAssetVersion('/assets/icons/ui/ui_nearby.webp')
}

export function uiInkSplatAssetPath(): string {
  return withAssetVersion('/assets/icons/ui/ui_ink_splat.webp')
}
