import 'package:ik_content/ik_content.dart';

/// Bundle keys for the shared art in `content/assets`.
///
/// The tables mirror `src/game/assets/assetMap.ts`, and the paths only differ by
/// the `content/` prefix Flutter needs, since both clients read the same files.
/// No cache-busting query: a Flutter bundle is versioned by the build itself.

const String _assetRoot = 'content/assets';

const Map<String, String> _mapArt = <String, String>{
  'MAP-0001': 'maps/map_idale_main.png',
  'MAP-0002': 'maps/map_mountain_caves.png',
  'MAP-0003': 'maps/map_castle_grounds.png',
  'MAP-0004': 'maps/map_idale_west.png',
  'MAP-0005': 'maps/map_idale_east.png',
  'MAP-0006': 'maps/map_town.png',
  // Temporary reuse until dedicated Citadel map art exists.
  'MAP-0007': 'maps/map_town.png',
};

const Map<String, String> _locationArt = <String, String>{
  'LOC-0001': 'locations/loc_farm.png',
  'LOC-0002': 'locations/loc_town.png',
  'LOC-0003': 'locations/loc_goblin_camp.png',
  'LOC-0004': 'locations/loc_river_coast_dock.png',
  'LOC-0005': 'locations/loc_copper_mine.png',
  'LOC-0006': 'locations/loc_mountains.png',
  'LOC-0007': 'locations/loc_wizards_tower.png',
  'LOC-0008': 'locations/loc_kingswoods.png',
  'LOC-0009': 'locations/loc_meadow.png',
  'LOC-0010': 'locations/loc_cave_entrance.png',
  'LOC-0011': 'locations/loc_deep_mines.png',
  'LOC-0012': 'locations/loc_dwarven_mining_store.png',
  'LOC-0013': 'locations/loc_castle.png',
  'LOC-0014': 'locations/loc_castle_courtyard.png',
  'LOC-0015': 'locations/loc_castle_main_hall.png',
  'LOC-0016': 'locations/loc_kings_quarters.png',
  'LOC-0017': 'locations/loc_castle_barracks.png',
  'LOC-0018': 'locations/loc_ancient_forest.png',
  // Temporary reuse until dedicated art exists.
  'LOC-0021': 'locations/loc_kings_quarters.png',
  'LOC-0022': 'locations/loc_deep_mines.png',
  'LOC-0023': 'locations/loc_town_kitchen.png',
  'LOC-0024': 'locations/loc_town_general_store.png',
  'LOC-0025': 'locations/loc_town_foundry.png',
  'LOC-0026': 'locations/loc_town_apothecary.png',
  // Temporary reuse until dedicated Citadel location art exists.
  'LOC-0027': 'locations/loc_castle.png',
  'LOC-0028': 'locations/loc_town.png',
  'LOC-0029': 'locations/loc_town_general_store.png',
  'LOC-0030': 'locations/loc_town_foundry.png',
  'LOC-0031': 'locations/loc_meadow.png',
  'LOC-0032': 'locations/loc_castle_barracks.png',
};

/// Item icons keyed by id, for the items whose art is not derived from tags.
const Map<String, String> _itemIcons = <String, String>{
  'ITEM-0001': 'gold',
  'ITEM-0006': 'coal',
  'ITEM-0011': 'essence',
  'ITEM-0025': 'potato',
  'ITEM-0026': 'potato',
  'ITEM-0028': 'berries',
  'ITEM-0046': 'dragon_scale',
  'ITEM-0058': 'baked_potato',
  'ITEM-0103': 'fishing_tool',
  'ITEM-0108': 'net',
  'ITEM-0111': 'copper_pickaxe',
  'ITEM-0119': 'steel_pickaxe',
  'ITEM-0123': 'hammer',
  'ITEM-0169': 'backpack',
  'ITEM-0288': 'insignia',
  'ITEM-0295': 'spell',
  'ITEM-0296': 'cosmetic_outfit_travelers_tunic',
};

String mapAssetPath(String mapId) {
  return '$_assetRoot/${_mapArt[mapId] ?? 'maps/map_idale_main.png'}';
}

String locationAssetPath(String locationId) {
  return '$_assetRoot/${_locationArt[locationId] ?? 'locations/loc_town.png'}';
}

/// An item's icon, falling back to the generic one for anything unmapped.
String itemIconPath(String itemId) {
  return '$_assetRoot/icons/items/item_${_itemIcons[itemId] ?? 'default'}.png';
}

String skillIconPath(SkillRow? skill) {
  final key = skill?.raw['Internal Key'];
  if (key is! String) return '$_assetRoot/icons/skills/skl_combat.png';
  return '$_assetRoot/icons/skills/skl_${key.trim().toLowerCase().replaceAll(' ', '_')}.png';
}

String uiMapAssetPath() => '$_assetRoot/icons/ui/ui_map.png';
