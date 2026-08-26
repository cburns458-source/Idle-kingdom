import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../save/generated/save_models.dart';
import 'favorites.dart';

/// How the bag is ordered on screen. Group is the default.
enum InventorySortMode { group, az, search }

const int groupCombat = 1;
const int groupMining = 2;
const int groupMetallurgy = 3;
const int groupSmithing = 4;
const int groupArtisanry = 5;
const int groupCooking = 6;
const int groupFishing = 7;
const int groupHarvesting = 8;
const int groupHunting = 9;
const int groupWoodcutting = 10;
const int groupCrafting = 11;
const int groupAlchemy = 12;
const int groupArcana = 13;
const int groupOther = 14;

const Map<String, int> _skillGroup = <String, int>{
  'SKL-0002': groupMining,
  'SKL-0003': groupFishing,
  'SKL-0004': groupHarvesting,
  'SKL-0005': groupHunting,
  'SKL-0006': groupWoodcutting,
  'SKL-0007': groupCooking,
  'SKL-0008': groupMetallurgy,
  'SKL-0009': groupCrafting,
  'SKL-0010': groupAlchemy,
  'SKL-0011': groupSmithing,
  'SKL-0012': groupArtisanry,
  'SKL-0013': groupArcana,
};

const Map<String, int> _armorSlotRank = <String, int>{
  'SLOT-0003': 0,
  'SLOT-0004': 1,
  'SLOT-0005': 2,
  'SLOT-0006': 3,
  'SLOT-0007': 4,
};

const int _unknownTier = 80;
const int _unknownLevel = 999;

Set<String> _parseTags(String? value) {
  if (value == null || value.isEmpty) return const <String>{};
  return value
      .split(RegExp(r'[;,]'))
      .map((part) => part.trim().toLowerCase())
      .where((part) => part.isNotEmpty)
      .toSet();
}

int _metalTier(String name) {
  if (name.contains('ancient alloy')) return 11;
  if (name.contains('reinforced steel')) return 6;
  if (name.contains('moonstone')) return 13;
  if (name.contains('tungsten')) return 10;
  if (name.contains('titanium')) return 9;
  if (name.contains('aether')) return 12;
  if (name.contains('ancient')) return 11;
  if (RegExp(r'\bbronze\b').hasMatch(name)) return 3;
  if (RegExp(r'\bcopper\b').hasMatch(name)) return 1;
  if (RegExp(r'\btin\b').hasMatch(name)) return 2;
  if (RegExp(r'\biron\b').hasMatch(name)) return 4;
  if (RegExp(r'\bsteel\b').hasMatch(name)) return 5;
  if (RegExp(r'\bsilver\b').hasMatch(name)) return 7;
  if (RegExp(r'\bgold\b').hasMatch(name)) return 8;
  if (RegExp(r'\bwooden\b').hasMatch(name) || RegExp(r'\bregular\b').hasMatch(name)) {
    return 0;
  }
  return _unknownTier;
}

int _woodTier(String name) {
  if (name.contains('mahogany')) return 5;
  if (name.contains('maple')) return 4;
  if (name.contains('poplar')) return 3;
  if (name.contains('oak')) return 2;
  if (name.contains('cedar')) return 1;
  if (name.contains('ancient')) return 6;
  if (name.contains('wooden') || name.contains('regular')) return 0;
  return _unknownTier;
}

int _gemTier(String name) {
  if (name.contains('sapphire')) return 0;
  if (name.contains('emerald')) return 1;
  if (name.contains('ruby')) return 2;
  return _unknownTier;
}

void _rememberMin(Map<String, int> map, String? itemId, num? level) {
  if (itemId == null || itemId.isEmpty || level == null || !level.isFinite) return;
  final next = level.round();
  final current = map[itemId];
  if (current == null || next < current) map[itemId] = next;
}

/// Cached grouping ranks so a 180-slot bag does not rescan the database per compare.
class InventorySorter {
  InventorySorter(this.db) {
    for (final item in db.items) {
      _items[item.itemId] = item;
    }
    for (final row in db.equipment) {
      final slotId = row.slotId;
      if (isNotBlank(slotId)) _slotByItem[row.itemId] = slotId!;
    }
    for (final action in db.actions) {
      _rememberMin(_levels, action.targetId, action.proficiencyLevel);
    }
    for (final recipe in db.recipes) {
      final output = recipe.raw['Output Item ID'];
      final level = recipe.raw['Proficiency Level'];
      if (output is String) _rememberMin(_levels, output, level is num ? level : null);
    }
    for (final project in db.projects) {
      final output = project.raw['Output Item / Target ID'];
      final level = project.raw['Required Skill 1 Level'];
      if (output is String) _rememberMin(_levels, output, level is num ? level : null);
    }
    for (final row in db.equipment) {
      _rememberMin(_levels, row.itemId, row.requiredLevel);
    }
  }

  final GameDatabase db;
  final Map<String, ItemRow> _items = <String, ItemRow>{};
  final Map<String, String> _slotByItem = <String, String>{};
  final Map<String, int> _levels = <String, int>{};

  String itemName(String itemId) => _items[itemId]?.displayName ?? itemId;

  bool itemMatchesName(String itemId, String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return itemName(itemId).toLowerCase().contains(needle);
  }

  /// Favorites first in every mode; Search filters by display name only.
  List<int> displayIndexes(
    List<InventoryStack> stacks,
    InventorySortMode mode, [
    String query = '',
  ]) {
    var indexes = [for (var i = 0; i < stacks.length; i++) i];
    if (mode == InventorySortMode.search) {
      final needle = query.trim();
      if (needle.isNotEmpty) {
        indexes = [
          for (final index in indexes)
            if (itemMatchesName(stacks[index].itemId, needle)) index,
        ];
      }
    }
    indexes.sort((a, b) {
      return mode == InventorySortMode.az
          ? compareAz(stacks[a], stacks[b], a, b)
          : compareGrouped(stacks[a], stacks[b], a, b);
    });
    return indexes;
  }

  int compareGrouped(InventoryStack a, InventoryStack b, [int aIndex = 0, int bIndex = 0]) {
    final favorite = _compareFavorite(a, b);
    if (favorite != 0) return favorite;
    final keyA = groupedKey(a.itemId);
    final keyB = groupedKey(b.itemId);
    final compared = _compareKeys(keyA, keyB);
    if (compared != 0) return compared;
    return aIndex - bIndex;
  }

  int compareAz(InventoryStack a, InventoryStack b, [int aIndex = 0, int bIndex = 0]) {
    final favorite = _compareFavorite(a, b);
    if (favorite != 0) return favorite;
    final name = itemName(a.itemId).toLowerCase().compareTo(itemName(b.itemId).toLowerCase());
    if (name != 0) return name;
    final ids = a.itemId.compareTo(b.itemId);
    if (ids != 0) return ids;
    return aIndex - bIndex;
  }

  int _compareFavorite(InventoryStack a, InventoryStack b) {
    final aFavorite = isFavoriteStack(a) ? 0 : 1;
    final bFavorite = isFavoriteStack(b) ? 0 : 1;
    return aFavorite - bFavorite;
  }

  List<Object> groupedKey(String itemId) {
    final item = _items[itemId];
    final name = (item?.displayName ?? itemId).toLowerCase();
    final category = (item?.category ?? '').toLowerCase();
    final subtype = (item?.subtype ?? '').toLowerCase();
    final tags = _parseTags(item?.functionalSourceTags);
    final slot = _slotByItem[itemId] ?? item?.equipmentSlotId ?? '';
    final group = _resolveGroup(item, tags, category, subtype, name);
    final family = _family(group, tags, category, subtype, name);
    final rank = _rank(group, family, name, itemId);
    final slotRank = _armorSlotRank[slot] ?? 50;
    return <Object>[group, family, rank, slotRank, name, itemId];
  }

  int groupOf(String itemId) => groupedKey(itemId).first as int;

  int _resolveGroup(ItemRow? item, Set<String> tags, String category, String subtype, String name) {
    if (subtype == 'timber' || name.endsWith(' timber')) return groupWoodcutting;
    if (category == 'spell component' || category == 'spell' || tags.contains('spell')) {
      return groupArcana;
    }

    final skill = item?.associatedSkillId;
    if (skill == 'SKL-0001') {
      if (category == 'raw food' || tags.contains('cooking_input')) return groupHunting;
      return groupCombat;
    }
    final fromSkill = skill == null ? null : _skillGroup[skill];
    if (fromSkill != null) return fromSkill;

    if (tags.contains('mining_tool')) return groupMining;
    if (tags.contains('fishing_tool')) return groupFishing;
    if (tags.contains('woodcutting_tool')) return groupWoodcutting;
    if (tags.contains('hunting_tool')) return groupHunting;
    if (tags.contains('metallurgy_time_modifier') || subtype.contains('metallurgy')) {
      return groupMetallurgy;
    }

    if (category == 'weapon' ||
        category == 'armor' ||
        category == 'shield / off-hand' ||
        tags.contains('combat_weapon') ||
        tags.contains('combat_armor') ||
        tags.contains('combat_defense')) {
      return groupCombat;
    }

    if (category == 'raw food' || tags.contains('cooking_input') || tags.contains('food_slot')) {
      if (tags.contains('fishing_output')) return groupFishing;
      if (tags.contains('harvesting_output')) return groupHarvesting;
      return groupHunting;
    }

    if (subtype.contains('creature') ||
        subtype.contains('hide') ||
        name.contains('leather') ||
        tags.contains('hunting_output')) {
      return groupHunting;
    }

    if (subtype.contains('forest') ||
        name.contains('heartwood') ||
        name.contains('bark') ||
        RegExp(r'\bsap\b').hasMatch(name)) {
      return groupWoodcutting;
    }

    if (tags.contains('arcana_input') ||
        tags.contains('arcana_output') ||
        tags.contains('arcana_equipment')) {
      return groupArcana;
    }

    return groupOther;
  }

  int _family(int group, Set<String> tags, String category, String subtype, String name) {
    switch (group) {
      case groupCombat:
        if (category == 'weapon' ||
            (tags.contains('combat_weapon') && category != 'shield / off-hand')) {
          return 0;
        }
        if (category == 'shield / off-hand' || tags.contains('combat_defense')) return 1;
        if (category == 'armor' || tags.contains('combat_armor')) return 2;
        return 3;
      case groupMining:
        if (tags.contains('mining_tool') ||
            subtype.contains('pickaxe') ||
            name.contains('pickaxe')) {
          return 0;
        }
        if (subtype.contains('ore')) return 2;
        if (subtype == 'gem' || _gemTier(name) != _unknownTier) return 3;
        if (name.contains('essence') || subtype.contains('magical')) return 4;
        if (subtype.contains('mineral') ||
            subtype.contains('fuel') ||
            name == 'clay' ||
            name == 'coal') {
          return 1;
        }
        return 5;
      case groupFishing:
        if (category == 'tool' || tags.contains('fishing_tool')) {
          if (name.contains('rod')) return 0;
          if (name.contains('net')) return 1;
          if (name.contains('harpoon')) return 2;
          return 3;
        }
        if (category == 'raw food' || tags.contains('fishing_output')) return 4;
        return 5;
      case groupHarvesting:
        if (subtype.contains('crop')) return 0;
        if (subtype.contains('herb') ||
            subtype.contains('weed') ||
            name.contains('blossom') ||
            subtype.contains('wild plant')) {
          return 1;
        }
        return 2;
      case groupHunting:
        if (tags.contains('hunting_tool') || category == 'tool' || name.contains('bow')) return 0;
        if (subtype.contains('hide') || name.contains('leather') || subtype.contains('processed')) {
          return 1;
        }
        if (category == 'raw food' ||
            name.contains('meat') ||
            name.contains('beef') ||
            name.contains('venison')) {
          return 2;
        }
        return 3;
      case groupWoodcutting:
        if (tags.contains('woodcutting_tool') ||
            name.contains('hatchet') ||
            RegExp(r'\baxe\b').hasMatch(name)) {
          return 0;
        }
        if (subtype == 'log' || name.endsWith(' log')) return 1;
        if (subtype == 'timber' || name.endsWith(' timber')) return 2;
        return 3;
      case groupCooking:
        if (category == 'food' || tags.contains('cooking_output') || tags.contains('food_slot')) {
          return 0;
        }
        if (category == 'armor' || category == 'tool') return 1;
        return 2;
      case groupMetallurgy:
        if (category == 'tool' || name.contains('warhammer')) return 0;
        if (category == 'metal bar' ||
            tags.contains('metallurgy_output') ||
            name.endsWith(' bar')) {
          return 1;
        }
        return 2;
      case groupCrafting:
        return category == 'component' ? 0 : 1;
      case groupAlchemy:
        return category == 'potion' || tags.contains('alchemy_output') ? 0 : 1;
      case groupSmithing:
        if (category == 'tool') return 0;
        if (category == 'weapon') return 1;
        if (category == 'shield / off-hand') return 2;
        if (category == 'armor') return 3;
        return 4;
      case groupArtisanry:
        if (category == 'weapon' || category == 'tool' || tags.contains('hunting_tool')) return 0;
        if (category == 'jewelry') return 2;
        if (category == 'armor') return 1;
        return 3;
      case groupArcana:
        if (category == 'spell component' || name.contains('tablet') || name.contains('essence')) {
          return 0;
        }
        if (category == 'spell' || tags.contains('spell')) return 1;
        if (name.contains('staff') || name.contains('wand')) return 2;
        return 3;
      default:
        return 0;
    }
  }

  int _rank(int group, int family, String name, String itemId) {
    if (group == groupMining) {
      if (family == 0 || family == 2) return _metalTier(name);
      if (family == 3) return _gemTier(name);
      return 0;
    }
    if (group == groupWoodcutting) {
      if (family == 0) return _metalTier(name);
      if (family == 1 || family == 2) return _woodTier(name);
      return 0;
    }
    if (group == groupMetallurgy || group == groupSmithing) return _metalTier(name);
    if (group == groupArtisanry) {
      final wood = _woodTier(name);
      if (wood != _unknownTier) return wood;
      final gem = _gemTier(name);
      if (gem != _unknownTier) return gem;
      return _metalTier(name);
    }
    if (group == groupFishing ||
        group == groupHarvesting ||
        group == groupCooking ||
        group == groupAlchemy ||
        group == groupHunting) {
      return _levels[itemId] ?? _unknownLevel;
    }
    if (group == groupArcana) return _levels[itemId] ?? _unknownLevel;
    if (group == groupCombat) {
      final metal = _metalTier(name);
      if (metal != _unknownTier) return metal;
      return _levels[itemId] ?? _unknownLevel;
    }
    return 0;
  }
}

int _compareKeys(List<Object> a, List<Object> b) {
  final length = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    final left = a[i];
    final right = b[i];
    if (left is num && right is num) {
      final compared = left.compareTo(right);
      if (compared != 0) return compared;
      continue;
    }
    final compared = '$left'.compareTo('$right');
    if (compared != 0) return compared;
  }
  return a.length.compareTo(b.length);
}

List<int> inventoryDisplayIndexes(
  GameDatabase db,
  List<InventoryStack> stacks,
  InventorySortMode mode, [
  String query = '',
]) {
  return InventorySorter(db).displayIndexes(stacks, mode, query);
}
