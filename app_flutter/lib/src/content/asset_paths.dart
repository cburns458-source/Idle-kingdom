import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

/// Bundle keys for the shared art in `content/assets`.
///
/// The tables mirror `src/game/assets/`, and the paths only differ by the
/// `content/` prefix Flutter needs. No cache-busting query: a Flutter bundle is
/// versioned by the build itself. Art is WebP: lossless for sprites, lossy for
/// the location and map backgrounds. Most location plates are 1080×1920
/// (9:16), matching the main maps. Town, the cave entrance, and the castle
/// gateway are still the old 384px squares until those plates are redrawn.

const String _assetRoot = 'content/assets';

const Map<String, String> _mapArt = <String, String>{
  'MAP-0001': 'maps/map_idale_main.webp',
  'MAP-0002': 'maps/map_mountain_caves.webp',
  'MAP-0003': 'maps/map_castle_grounds.webp',
  'MAP-0004': 'maps/map_idale_west.webp',
  'MAP-0005': 'maps/map_idale_east.webp',
  'MAP-0006': 'maps/map_town.webp',
  'MAP-0007': 'maps/map_citadel.webp',
};

const Map<String, String> _locationArt = <String, String>{
  'LOC-0001': 'locations/loc_farm.webp',
  'LOC-0002': 'locations/loc_town.webp',
  'LOC-0003': 'locations/loc_goblin_camp.webp',
  'LOC-0004': 'locations/loc_river_coast_dock.webp',
  'LOC-0005': 'locations/loc_copper_mine.webp',
  'LOC-0006': 'locations/loc_mountains.webp',
  'LOC-0007': 'locations/loc_wizards_tower.webp',
  'LOC-0008': 'locations/loc_kingswoods.webp',
  'LOC-0009': 'locations/loc_meadow.webp',
  'LOC-0010': 'locations/loc_cave_entrance.webp',
  'LOC-0011': 'locations/loc_deep_mines.webp',
  'LOC-0012': 'locations/loc_dwarven_mining_store.webp',
  'LOC-0013': 'locations/loc_castle.webp',
  'LOC-0014': 'locations/loc_castle_courtyard.webp',
  'LOC-0015': 'locations/loc_castle_main_hall.webp',
  'LOC-0016': 'locations/loc_kings_quarters.webp',
  'LOC-0017': 'locations/loc_castle_barracks.webp',
  'LOC-0018': 'locations/loc_ancient_forest.webp',
  'LOC-0021': 'locations/loc_queens_quarters.webp',
  'LOC-0022': 'locations/loc_abandoned_mineshaft.webp',
  'LOC-0023': 'locations/loc_town_kitchen.webp',
  'LOC-0024': 'locations/loc_town_general_store.webp',
  'LOC-0025': 'locations/loc_town_foundry.webp',
  'LOC-0026': 'locations/loc_town_apothecary.webp',
  'LOC-0027': 'locations/loc_citadel_gateway.webp',
  'LOC-0028': 'locations/loc_citadel_plaza.webp',
  'LOC-0029': 'locations/loc_citadel_market.webp',
  'LOC-0030': 'locations/loc_citadel_processing.webp',
  'LOC-0031': 'locations/loc_citadel_gathering.webp',
  'LOC-0032': 'locations/loc_citadel_combat.webp',
  'LOC-0033': 'locations/loc_guild_hall.webp',
  'LOC-0034': 'locations/loc_town_bank.webp',
  'LOC-0035': 'locations/loc_citadel_bank.webp',
  'LOC-0036': 'locations/loc_temple.webp',
};

/// Item icons keyed by id, for the items whose art the heuristic cannot infer.
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
  'ITEM-0288': 'insignia',
  'ITEM-0295': 'spell',
  'ITEM-0296': 'cosmetic_outfit_travelers_tunic',
};

const Map<String, String> _slotIcons = <String, String>{
  'SLOT-0001': 'weapon_tool',
  'SLOT-0002': 'offhand',
  'SLOT-0003': 'helmet',
  'SLOT-0004': 'chest',
  'SLOT-0005': 'legs',
  'SLOT-0006': 'boots',
  'SLOT-0007': 'gloves',
  'SLOT-0008': 'necklace',
  'SLOT-0009': 'ring',
  'SLOT-0010': 'back',
  'SLOT-0011': 'food',
  'SLOT-0012': 'potion',
  'SLOT-0013': 'spell_1',
  'SLOT-0014': 'spell_2',
  'SLOT-0015': 'spell_3',
  'SLOT-0016': 'spell_4',
};

const Map<String, String> _enemyArt = <String, String>{
  'ENM-0001': 'enemies/enm_cow.webp',
  'ENM-0002': 'enemies/enm_bull.webp',
  'ENM-0003': 'enemies/enm_goblin_scout.webp',
  'ENM-0004': 'enemies/enm_goblin_chief.webp',
  'ENM-0005': 'enemies/enm_pirate.webp',
  'ENM-0006': 'enemies/enm_dragon.webp',
  'ENM-0007': 'enemies/enm_rock_troll.webp',
  'ENM-0008': 'enemies/enm_skeleton.webp',
  'ENM-0009': 'enemies/enm_zombie.webp',
  'ENM-0010': 'enemies/enm_wild_boar.webp',
  'ENM-0011': 'enemies/enm_castle_guard.webp',
  'ENM-0012': 'enemies/enm_ent.webp',
  'ENM-0013': 'enemies/enm_ancient_ent.webp',
  'ENM-0014': 'enemies/enm_corrupted_ent.webp',
  'ENM-0016': 'enemies/enm_goblin_warrior.webp',
  'ENM-0018': 'enemies/enm_elder_rock_troll.webp',
  'ENM-0019': 'enemies/enm_castle_guard.webp',
  'ENM-0020': 'enemies/enm_castle_guard.webp',
  'ENM-0021': 'enemies/enm_seagull.webp',
};

/// Transparent workstation art for Standard Production stations.
const Map<String, String> _workstationArt = <String, String>{
  'FAC-0001': 'workstations/ws_cooking_stove.webp',
  'FAC-0003': 'workstations/ws_crafting_bench.webp',
  'FAC-0004': 'workstations/ws_metallurgy_furnace.webp',
  'FAC-0006': 'workstations/ws_alchemy_apothecary.webp',
};

/// Gathering action scene sprites keyed by Action ID.
const Map<String, String> _actionArt = <String, String>{
  'ACN-0013': 'actions/acn_hunt_duck.webp',
  'ACN-0014': 'actions/acn_hunt_elk.webp',
  'ACN-0015': 'actions/acn_hunt_butterfly.webp',
  'ACN-0016': 'actions/acn_hunt_rabbit.webp',
  'ACN-0017': 'actions/acn_hunt_pheasant.webp',
  'ACN-0018': 'actions/acn_mine_copper.webp',
  'ACN-0019': 'actions/acn_dig_clay.webp',
  'ACN-0020': 'actions/acn_mine_tin.webp',
  'ACN-0021': 'actions/acn_mine_coal.webp',
  'ACN-0022': 'actions/acn_mine_iron.webp',
  'ACN-0026': 'actions/acn_mine_titanium.webp',
  'ACN-0027': 'actions/acn_mine_tungsten.webp',
  'ACN-0028': 'actions/acn_delve_essence.webp',
  'ACN-0035': 'actions/acn_harvest_potato.webp',
  'ACN-0036': 'actions/acn_harvest_potato_golden.webp',
  'ACN-0046': 'actions/acn_cut_cedar.webp',
  'ACN-0047': 'actions/acn_cut_oak.webp',
  'ACN-0048': 'actions/acn_cut_poplar.webp',
  'ACN-0049': 'actions/acn_cut_maple.webp',
  'ACN-0050': 'actions/acn_cut_mahogany.webp',
  'ACN-0051': 'actions/acn_cut_ancient.webp',
  'ACN-0097': 'actions/acn_mine_silver.webp',
  'ACN-0098': 'actions/acn_mine_gold.webp',
  'ACN-0099': 'actions/acn_catch_crawfish.webp',
  'ACN-0100': 'actions/acn_catch_trout.webp',
  'ACN-0101': 'actions/acn_catch_salmon.webp',
  'ACN-0102': 'actions/acn_catch_tuna.webp',
  'ACN-0103': 'actions/acn_catch_shark.webp',
  'ACN-0104': 'actions/acn_catch_baby_giant_squid.webp',
  'ACN-0105': 'actions/acn_gather_wild_roots.webp',
  'ACN-0106': 'actions/acn_gather_fernleaf.webp',
  'ACN-0107': 'actions/acn_gather_mosstole.webp',
  'ACN-0108': 'actions/acn_gather_wild_berries.webp',
  'ACN-0109': 'actions/acn_gather_augur_weed.webp',
  'ACN-0110': 'actions/acn_gather_moonblossom.webp',
  'ACN-0111': 'actions/acn_gather_starroot.webp',
  'ACN-0112': 'actions/acn_hunt_mountain_goat.webp',
  'ACN-0113': 'actions/acn_hunt_great_stag.webp',
  'ACN-0114': 'actions/acn_hunt_moonhorn_elk.webp',
  'ACN-0162': 'actions/acn_gather_carrot.webp',
  'ACN-0163': 'actions/acn_gather_grapes.webp',
  'ACN-0166': 'actions/acn_mine_sapphire.webp',
  'ACN-0167': 'actions/acn_mine_emerald.webp',
  'ACN-0168': 'actions/acn_mine_ruby.webp',
};

const Map<String, String> _genderArt = <String, String>{
  'APR-0017': 'player/player_gender_feminine.webp',
  'APR-0019': 'player/player_gender_androgynous.webp',
  'APR-0018': 'player/player_gender_masculine.webp',
};

/// Whether the art tables name this id rather than answering with a fallback.
///
/// The fallbacks are there so an unmapped id cannot break a screen; these say
/// whether one was needed, which is what the asset audit checks.
bool hasMapArt(String mapId) => _mapArt.containsKey(mapId);

bool hasLocationArt(String locationId) => _locationArt.containsKey(locationId);

bool hasEnemyArt(String enemyId) => _enemyArt.containsKey(enemyId);

bool hasActionArt(String actionId) => _actionArt.containsKey(actionId);

String mapAssetPath(String mapId) {
  return '$_assetRoot/${_mapArt[mapId] ?? 'maps/map_idale_main.webp'}';
}

String locationAssetPath(String locationId) {
  return '$_assetRoot/${_locationArt[locationId] ?? 'locations/loc_town.webp'}';
}

/// An item's icon, by id when one is pinned and by [itemIconStem] otherwise.
String itemIconPath(ItemRow? item) {
  return '$_assetRoot/icons/items/item_${itemIconStem(item)}.webp';
}

/// The coin, for gold amounts that are not an inventory stack.
String goldIconPath() => '$_assetRoot/icons/items/item_gold.webp';

String slotIconPath(String slotId) {
  return '$_assetRoot/icons/slots/slot_${_slotIcons[slotId] ?? 'weapon_tool'}.webp';
}

String enemyAssetPath(String enemyId) {
  return '$_assetRoot/${_enemyArt[enemyId] ?? 'enemies/enm_cow.webp'}';
}

String workstationAssetPath(String? facilityId) {
  const fallback = 'workstations/ws_crafting_bench.webp';
  return '$_assetRoot/${_workstationArt[facilityId] ?? fallback}';
}

String actionAssetPath(String actionId) {
  return '$_assetRoot/${_actionArt[actionId] ?? 'actions/acn_harvest_potato.webp'}';
}

String critterAssetPath(String internalKey) => '$_assetRoot/critters/crt_$internalKey.webp';

String skillIconPath(SkillRow? skill) {
  if (skill == null) return '$_assetRoot/icons/skills/skl_combat.webp';
  final key = skill.internalKey.trim().toLowerCase().replaceAll(' ', '_');
  return '$_assetRoot/icons/skills/skl_$key.webp';
}

/// The player sprite, used for the portrait and the action scenes alike.
String playerAssetPath(PlayerAppearance? appearance) {
  final art = _genderArt[appearance?.genderPresentation] ?? _genderArt[defaultGenderPresentationId];
  return '$_assetRoot/${art ?? 'player/player_gender_feminine.webp'}';
}

String uiMapAssetPath() => '$_assetRoot/icons/ui/ui_map.webp';

/// The pixel ring drawn over the HUD portrait.
String avatarFrameAssetPath() => '$_assetRoot/player/avatar_frame_pixel.webp';

/// Picks an item's icon from its row key, then id, then category and name.
///
/// A port of `iconStemFromText` in `src/game/assets/itemAssets.ts`, order
/// included: the tests there pin cases the order decides, like "platelegs"
/// resolving as legs rather than as a chest plate.
String itemIconStem(ItemRow? item) {
  if (item == null) return 'default';
  final fromRow = item.iconAssetKey?.trim();
  if (fromRow != null && fromRow.isNotEmpty) return fromRow;
  final pinned = _itemIcons[item.itemId];
  if (pinned != null) return pinned;

  final category = (item.category ?? '').toLowerCase();
  final subtype = (item.subtype ?? '').toLowerCase();
  final blob =
      '${item.internalKey.toLowerCase()} $category $subtype ${item.displayName.toLowerCase()}';

  if (blob.contains('gold') && (category.contains('currency') || blob.contains('coin'))) {
    return 'gold';
  }
  if (blob.contains('essence')) return 'essence';
  if (blob.contains('coal')) return 'coal';
  if (blob.contains('potato') || blob.contains('spud')) {
    return blob.contains('baked') ? 'baked_potato' : 'potato';
  }
  if (blob.contains('quiver') ||
      blob.contains('backpack') ||
      blob.contains('back item') ||
      subtype.contains('back')) {
    return 'backpack';
  }
  if (blob.contains('fishing') || blob.contains('rod') || blob.contains('harpoon')) {
    return 'fishing_tool';
  }
  if (blob.contains('warhammer') || blob.contains('hammer')) return 'hammer';
  if (blob.contains('necklace') || blob.contains('amulet')) return 'necklace';
  if (RegExp(r'\bring\b').hasMatch(blob) || subtype.contains('ring')) return 'ring';
  if (blob.contains('sapphire') ||
      blob.contains('emerald') ||
      blob.contains('ruby') ||
      blob.contains('gem')) {
    return 'gem';
  }
  if (blob.contains('timber') || blob.contains('plank')) return 'timber';
  if (blob.contains('leather') ||
      blob.contains('strap') ||
      blob.contains('cloth') ||
      blob.contains('component') ||
      blob.contains('tablet') ||
      blob.contains('chain') ||
      blob.contains('clasp') ||
      blob.contains('fiber') ||
      category.contains('component')) {
    return 'component';
  }
  if (blob.contains('net') || blob.contains('sling')) return 'net';
  if (blob.contains('pickaxe') || RegExp(r'\bpick\b').hasMatch(blob)) return 'pickaxe';
  if (blob.contains('hatchet')) return 'hatchet';
  if (blob.contains('bow')) return 'bow';
  if (blob.contains('sword')) return 'sword';
  if (blob.contains('dagger')) return 'dagger';
  if (blob.contains('axe') && !blob.contains('pickaxe')) return 'axe';
  if (blob.contains('shield') || blob.contains('off-hand') || blob.contains('offhand')) {
    return 'shield';
  }
  if (blob.contains('helmet') || blob.contains('hat')) return 'helmet';
  // Legs before chest so "platelegs" does not resolve as chest plate.
  if (blob.contains('leg') || blob.contains('plateleg') || subtype.contains('plateleg')) {
    return 'legs';
  }
  if (blob.contains('chest') || blob.contains('plate') || blob.contains('mail')) return 'chest';
  if (blob.contains('boot')) return 'boots';
  if (blob.contains('glove')) return 'gloves';
  if (blob.contains('potion') || blob.contains('vial')) return 'potion';
  if (RegExp(r'\bore\b').hasMatch(blob) || subtype.contains('ore') || category.contains('ore')) {
    return 'ore';
  }
  if (blob.contains('bar') || category.contains('metal bar')) return 'bar';
  if (blob.contains('log') || blob.contains('wood')) return 'log';
  if (blob.contains('herb') || blob.contains('fern') || blob.contains('weed')) return 'herb';
  if (blob.contains('hide') ||
      blob.contains('meat') ||
      blob.contains('feather') ||
      blob.contains('creature') ||
      blob.contains('bone')) {
    return 'creature';
  }
  if (blob.contains('berry') ||
      blob.contains('berrie') ||
      blob.contains('grape') ||
      blob.contains('carrot') ||
      blob.contains('clay') ||
      blob.contains('root')) {
    return 'raw_food';
  }
  if (blob.contains('dragon') && blob.contains('scale')) return 'dragon_scale';
  if (blob.contains('insignia')) return 'insignia';
  // Prepared spells only — not "Spell Component" tablets.
  if (category == 'spell') return 'spell';
  if (category.contains('food') || subtype.contains('food')) return 'food';
  if (category.contains('raw')) return 'raw_food';
  if (category.contains('weapon') || category.contains('tool')) return 'sword';
  if (category.contains('armor')) return 'chest';
  return 'default';
}
