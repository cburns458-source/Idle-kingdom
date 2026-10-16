import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/requirements.dart';
import '../combat/stats.dart' show mightSkillId, vitalitySkillId;
import '../equipment/specialist.dart'
    show alchemyRecipeUsesPotionDie, alchemySkillId, cookingSkillId;
import '../js_compat.dart';
import '../npcs/knowledge.dart';
import '../production/recipes.dart';
import '../projects/projects.dart';
import '../timers/location_timers.dart'
    show botanyPlantDisplayName, fishingPotItemId, potFishByLocation;

const String _essenceItemId = 'ITEM-0011';
const String miningSkillId = 'SKL-0002';
const String fishingSkillId = 'SKL-0003';
const String harvestingSkillId = 'SKL-0004';
const String huntingSkillId = 'SKL-0005';
const String woodcuttingSkillId = 'SKL-0006';
const String botanySkillMenuId = 'SKL-0014';
const String thieverySkillMenuId = 'SKL-0015';

const List<String> _woodenMiningTools = <String>['ITEM-0102'];
const List<String> _woodenWoodcuttingTools = <String>['ITEM-0100', 'ITEM-0101'];
const List<String> _woodenFishingTools = <String>['ITEM-0103'];
const List<String> _woodenHuntingTools = <String>['ITEM-0108', 'ITEM-0109'];
const List<String> _woodenCombatGear = <String>['ITEM-0124', 'ITEM-0125', 'ITEM-0145'];

const String _magicBolaItemId = 'ITEM-0315';

const List<String> _combatArmorWords = <String>[
  'Helmet',
  'Chestplate',
  'Platelegs',
  'Boots',
  'Gloves',
  'Shield',
];

const List<String> _combatWeaponWords = <String>['Sword', 'Dagger', 'Warhammer', 'Battleaxe'];

/// One row of a skill menu: what it makes and the level it needs.
class SkillMenuListItem {
  const SkillMenuListItem({required this.id, required this.displayName, required this.level});

  final String id;
  final String displayName;

  /// Proficiency or required skill level, null when the row has none.
  final num? level;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'displayName': displayName,
    'level': level,
  };
}

/// A labeled group inside a skill-menu tab.
class SkillMenuSection {
  const SkillMenuSection({this.title, required this.entries});

  final String? title;
  final List<SkillMenuListItem> entries;

  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'entries': [for (final entry in entries) entry.toJson()],
  };
}

/// One tab of a skill menu.
class SkillMenuTab {
  const SkillMenuTab({required this.id, required this.label, required this.sections});

  final String id;
  final String label;
  final List<SkillMenuSection> sections;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'label': label,
    'sections': [for (final section in sections) section.toJson()],
  };
}

/// Tabbed catalog shown when a skill tile is opened.
class SkillMenuView {
  const SkillMenuView({required this.skillId, required this.tabs, required this.showRecipeBook});

  final String skillId;
  final List<SkillMenuTab> tabs;
  final bool showRecipeBook;

  Map<String, Object?> toJson() => <String, Object?>{
    'skillId': skillId,
    'showRecipeBook': showRecipeBook,
    'tabs': [for (final tab in tabs) tab.toJson()],
  };
}

/// Activities that can roll [actionId] from their pool.
List<ActivityRow> activitiesForAction(GameDatabase db, String actionId) {
  final poolIds = <String>{
    for (final entry in db.poolEntries)
      if (entry.raw['Action ID'] == actionId) jsString(entry.raw['Pool ID']),
  };
  if (poolIds.isEmpty) return const <ActivityRow>[];
  return [
    for (final activity in db.activities)
      if (poolIds.contains(activity.poolId)) activity,
  ];
}

bool _isQuestOnlyRequirement(RequirementRow requirement) {
  final type = requirement.requirementType;
  return type == 'Quest Access' ||
      type == 'Quest Flag' ||
      type == 'Quest Active' ||
      type == 'Quest Complete' ||
      type == 'Quest Step';
}

/// True when every activity that can roll this action is quest-gated.
bool actionIsQuestOnly(GameDatabase db, String actionId) {
  final activities = activitiesForAction(db, actionId);
  if (activities.isEmpty) return false;
  return activities.every((activity) {
    return requirementsForEntity(db, 'Activity', activity.activityId).any(_isQuestOnlyRequirement);
  });
}

bool _isGatheringSkillMenuAction(ActionRow action) {
  return action.category != 'Combat';
}

String _thieveryActionNotes(ActionRow action) => action.notes ?? '';

/// Lockpick / safe / deposit-box thievery (RequiresLockpick family).
bool isThieveryLockpickAction(ActionRow action) {
  final notes = _thieveryActionNotes(action);
  return RegExp(r'RequiresLockpick', caseSensitive: false).hasMatch(notes) ||
      RegExp(r'ThieveryLockpick', caseSensitive: false).hasMatch(notes) ||
      RegExp(r'BankThievery', caseSensitive: false).hasMatch(notes);
}

/// Menu-only: lockpick actions that still appear under the Shops tab.
bool isThieveryShopMenuAction(ActionRow action) {
  return RegExp(r'ThieveryShop', caseSensitive: false).hasMatch(_thieveryActionNotes(action));
}

/// Shop-style steals (ThieverySteal family), plus ThieveryShop-routed lockpicks.
bool isThieveryShopAction(ActionRow action) {
  if (action.raw['Relevant Skill ID'] != thieverySkillMenuId) return false;
  if (isThieveryShopMenuAction(action)) return true;
  if (isThieveryLockpickAction(action)) return false;
  final notes = _thieveryActionNotes(action);
  return RegExp(r'ThieverySteal', caseSensitive: false).hasMatch(notes) ||
      action.category == 'Gathering';
}

/// Actions for a skill menu: display names only, unique by name.
List<SkillMenuListItem> actionsForSkill(GameDatabase db, String skillId) {
  final rows = db.actions
      .where(
        (action) =>
            action.raw['Relevant Skill ID'] == skillId &&
            action.raw['Status'] != 'Needs Data' &&
            isNotBlank((action.raw['Display Name'] as String?)?.trim()) &&
            !actionIsQuestOnly(db, action.actionId),
      )
      .toList();

  mergeSort(rows, compare: _compareSkillActions);

  final seen = <String>{};
  final items = <SkillMenuListItem>[];
  for (final action in rows) {
    final displayName = jsString(action.raw['Display Name']).trim();
    if (!seen.add(displayName)) continue;
    final proficiency = action.raw['Proficiency Level'];
    items.add(
      SkillMenuListItem(
        id: jsString(action.raw['Action ID']),
        displayName: displayName,
        level: proficiency is num ? proficiency : null,
      ),
    );
  }
  return items;
}

/// Projects for smithing / artisanry / arcana: output item name and level.
List<SkillMenuListItem> projectsForSkill(GameDatabase db, String skillId) {
  final rows = db.projects
      .where((project) => project.raw['Skill ID'] == skillId && isCompleteProject(project))
      .toList();

  mergeSort(
    rows,
    compare: (a, b) {
      final aLevel = _projectLevelForSkill(a, skillId) ?? double.infinity;
      final bLevel = _projectLevelForSkill(b, skillId) ?? double.infinity;
      if (aLevel != bLevel) return aLevel < bLevel ? -1 : 1;
      return jsLocaleCompare(projectOutputName(db, a), projectOutputName(db, b));
    },
  );

  final seen = <String>{};
  final items = <SkillMenuListItem>[];
  for (final project in rows) {
    final displayName = projectOutputName(db, project);
    if (displayName.isEmpty || !seen.add(displayName)) continue;
    items.add(
      SkillMenuListItem(
        id: jsString(project.raw['Project ID']),
        displayName: displayName,
        level: _projectLevelForSkill(project, skillId),
      ),
    );
  }
  return items;
}

/// Combined skill menu rows: actions first, then projects.
List<SkillMenuListItem> skillMenuEntries(GameDatabase db, String skillId) {
  return <SkillMenuListItem>[...actionsForSkill(db, skillId), ...projectsForSkill(db, skillId)];
}

/// `{level}. {name}` for a skill-menu row.
String skillMenuLine(SkillMenuListItem item) {
  final level = item.level;
  if (level == null) return item.displayName;
  final number = level == level.roundToDouble() ? level.toInt() : level;
  return '$number. ${item.displayName}';
}

/// Tabbed catalog for a skill tile.
SkillMenuView skillMenuView(GameDatabase db, String skillId) {
  final tabs = _nonEmptyTabs(_tabsForSkill(db, skillId));
  return SkillMenuView(
    skillId: skillId,
    tabs: tabs.isEmpty
        ? <SkillMenuTab>[_listTab('actions', 'Actions', const <SkillMenuListItem>[])]
        : tabs,
    showRecipeBook: skillHasRecipeBook(db, skillId),
  );
}

/// Flattened tabs, used by older tests and parity.
List<SkillMenuListItem> skillMenuDisplayEntries(GameDatabase db, String skillId) {
  return [
    for (final tab in skillMenuView(db, skillId).tabs)
      for (final section in tab.sections) ...section.entries,
  ];
}

/// Whether this skill has production recipes or projects to put in a book.
bool skillHasRecipeBook(GameDatabase db, String skillId) {
  return db.recipes.any(
        (recipe) => recipe.raw['Skill ID'] == skillId && isCompleteRecipe(recipe),
      ) ||
      db.projects.any(
        (project) => project.raw['Skill ID'] == skillId && isCompleteProject(project),
      );
}

/// Where a named output belongs in the skill menu / recipe book.
class SkillMenuPlacement {
  const SkillMenuPlacement({required this.tabId, required this.tabLabel, this.sectionTitle});

  final String tabId;
  final String tabLabel;
  final String? sectionTitle;
}

SkillMenuPlacement skillMenuPlacementForOutput(
  GameDatabase db,
  String skillId,
  String displayName, [
  String outputId = '',
]) {
  if (skillId == smithingSkillId) {
    final material = _smithingMaterial(displayName);
    if (material != null) {
      return SkillMenuPlacement(
        tabId: 'basic-metal',
        tabLabel: 'Basic metal',
        sectionTitle: '$material items',
      );
    }
    return const SkillMenuPlacement(tabId: 'other', tabLabel: 'Other');
  }
  if (skillId == artisanrySkillId) {
    final item = _itemForOutput(db, outputId, displayName);
    if (_isBowItem(item)) {
      return const SkillMenuPlacement(tabId: 'bows', tabLabel: 'Bows');
    }
    if (_isJewelryItem(item)) {
      return const SkillMenuPlacement(tabId: 'jewelry', tabLabel: 'Jewelry');
    }
    final material = _armorMaterial(item?.displayName ?? displayName);
    if (material != null && _isGroupedArmorMaterial(material)) {
      return SkillMenuPlacement(
        tabId: 'other',
        tabLabel: 'Other',
        sectionTitle: '$material equipment',
      );
    }
    return const SkillMenuPlacement(tabId: 'other', tabLabel: 'Other');
  }
  if (skillId == arcanaSkillId) {
    final item = _itemForOutput(db, outputId, displayName);
    if (_isSpellItem(item, displayName)) {
      return const SkillMenuPlacement(tabId: 'spells', tabLabel: 'Spells');
    }
    if (_isArcanaWeaponItem(item, outputId, displayName)) {
      return const SkillMenuPlacement(tabId: 'equipment', tabLabel: 'Equipment');
    }
    return const SkillMenuPlacement(tabId: 'enchants', tabLabel: 'Enchants');
  }
  if (skillId == thieverySkillMenuId) {
    final action = outputId.isNotEmpty
        ? db.actions.firstWhereOrNull((row) => row.actionId == outputId)
        : db.actions.firstWhereOrNull((row) => _namesEqual(row.displayName, displayName));
    if (action != null && isThieveryShopAction(action)) {
      return const SkillMenuPlacement(tabId: 'shops', tabLabel: 'Shops');
    }
    if (action != null && isThieveryLockpickAction(action)) {
      return const SkillMenuPlacement(tabId: 'lockpicking', tabLabel: 'Lockpicking');
    }
    return const SkillMenuPlacement(tabId: 'shops', tabLabel: 'Shops');
  }
  if (skillId == cookingSkillId) {
    return _cookingPlacement(displayName);
  }
  if (skillId == alchemySkillId) {
    return _alchemyPlacement(db, displayName, outputId);
  }
  if (skillMenuView(db, skillId).tabs.any((tab) => tab.id == 'actions')) {
    return const SkillMenuPlacement(tabId: 'actions', tabLabel: 'Actions');
  }
  final first = skillMenuView(db, skillId).tabs.first;
  return SkillMenuPlacement(tabId: first.id, tabLabel: first.label);
}

String projectOutputName(GameDatabase db, ProjectRow project) {
  final outputId = project.raw['Output Item / Target ID'];
  if (outputId is! String || outputId.isEmpty) return jsString(project.raw['Display Name']);
  if (isEnchantmentOutput(outputId)) {
    final enchantment = getEnchantment(db, outputId)?.raw['Display Name'];
    return enchantment is String ? enchantment : jsString(project.raw['Display Name']);
  }
  final item = db.items
      .firstWhereOrNull((row) => row.raw['Item ID'] == outputId)
      ?.raw['Display Name'];
  return item is String ? item : jsString(project.raw['Display Name']);
}

List<SkillMenuTab> _tabsForSkill(GameDatabase db, String skillId) {
  if (skillId == mightSkillId) {
    return <SkillMenuTab>[
      _listTab('weapons', 'Weapons', _combatWeaponEntries(db)),
      _listTab('other', 'Other', _combatOtherWeaponEntries(db)),
    ];
  }
  if (skillId == vitalitySkillId) {
    return <SkillMenuTab>[
      _listTab('gear', 'Equipment', _combatEquipmentEntries(db)),
      _listTab('other', 'Other', _combatOtherEquipmentEntries(db)),
    ];
  }
  if (skillId == fishingSkillId) {
    return _fishingTabs(db);
  }
  if (skillId == cookingSkillId) {
    return _cookingTabs(db);
  }
  if (skillId == miningSkillId ||
      skillId == harvestingSkillId ||
      skillId == huntingSkillId ||
      skillId == woodcuttingSkillId) {
    return <SkillMenuTab>[
      _listTab('actions', 'Actions', _gatheringSkillActions(db, skillId)),
      _listTab('tools', 'Tools', _gatheringToolEntries(db, skillId)),
    ];
  }
  if (skillId == botanySkillMenuId) {
    return _botanyTabs(db);
  }
  if (skillId == thieverySkillMenuId) {
    return _thieveryTabs(db);
  }
  if (skillId == smithingSkillId) {
    return _smithingTabs(db);
  }
  if (skillId == artisanrySkillId) {
    return _artisanryTabs(db);
  }
  if (skillId == arcanaSkillId) {
    return _arcanaTabs(db);
  }
  if (skillId == alchemySkillId) {
    return _alchemyTabs(db);
  }
  return <SkillMenuTab>[_listTab('actions', 'Actions', skillMenuEntries(db, skillId))];
}

List<SkillMenuListItem> _gatheringSkillActions(GameDatabase db, String skillId) {
  final items = <SkillMenuListItem>[];
  for (final item in actionsForSkill(db, skillId)) {
    final action = db.actions.firstWhereOrNull((row) => row.actionId == item.id);
    if (action == null || !_isGatheringSkillMenuAction(action)) continue;
    items.add(item);
  }
  return items;
}

List<SkillMenuTab> _thieveryTabs(GameDatabase db) {
  final shops = <SkillMenuListItem>[];
  final lockpicking = <SkillMenuListItem>[];
  for (final item in actionsForSkill(db, thieverySkillMenuId)) {
    final action = db.actions.firstWhereOrNull((row) => row.actionId == item.id);
    if (action == null) continue;
    if (isThieveryShopAction(action)) {
      shops.add(item);
    } else if (isThieveryLockpickAction(action)) {
      lockpicking.add(item);
    }
  }
  return <SkillMenuTab>[
    _listTab('shops', 'Shops', shops),
    _listTab('lockpicking', 'Lockpicking', lockpicking),
  ];
}

const Set<String> _botanyCropSeedIds = <String>{
  'ITEM-0324',
  'ITEM-0339',
  'ITEM-0369',
  'ITEM-0340',
  'ITEM-0371',
};
const Set<String> _botanyHerbSeedIds = <String>{
  'ITEM-0333',
  'ITEM-0334',
  'ITEM-0336',
  'ITEM-0373',
  'ITEM-0350',
};
const Set<String> _botanyFlowerSeedIds = <String>{'ITEM-0337', 'ITEM-0375'};

String _botanyTabIdForPlant(String itemId, String tags) {
  if (_botanyCropSeedIds.contains(itemId)) return 'crops';
  if (_botanyHerbSeedIds.contains(itemId)) return 'herbs';
  if (_botanyFlowerSeedIds.contains(itemId)) return 'flowers';
  if (tags.contains('botany_sapling')) return 'trees';
  return 'fruit_trees';
}

List<SkillMenuTab> _botanyTabs(GameDatabase db) {
  final buckets = <String, List<SkillMenuListItem>>{
    'flowers': <SkillMenuListItem>[],
    'crops': <SkillMenuListItem>[],
    'herbs': <SkillMenuListItem>[],
    'trees': <SkillMenuListItem>[],
    'fruit_trees': <SkillMenuListItem>[],
  };
  for (final item in db.items) {
    if (item.releasePhase != 'Launch') continue;
    if (item.status != 'Confirmed' && item.status != 'Planned') continue;
    final tags = (item.functionalSourceTags ?? '').toLowerCase();
    if (!tags.contains('botany_seed') && !tags.contains('botany_sapling')) continue;
    final notes = item.notes ?? '';
    final level =
        num.tryParse(
          RegExp(r'RequiresLevel:(\d+)', caseSensitive: false).firstMatch(notes)?.group(1) ?? '',
        ) ??
        1;
    final entry = SkillMenuListItem(
      id: item.itemId,
      displayName: botanyPlantDisplayName(item.displayName),
      level: level < 1 ? 1 : level,
    );
    final tabId = _botanyTabIdForPlant(item.itemId, tags);
    (buckets[tabId] ?? buckets['fruit_trees']!).add(entry);
  }
  for (final entries in buckets.values) {
    entries.sort((a, b) {
      final level = (a.level ?? 0).compareTo(b.level ?? 0);
      if (level != 0) return level;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
  }
  return <SkillMenuTab>[
    _listTab('crops', 'Crops', buckets['crops']!),
    _listTab('herbs', 'Herbs', buckets['herbs']!),
    _listTab('flowers', 'Flowers', buckets['flowers']!),
    _listTab('trees', 'Trees', buckets['trees']!),
    _listTab('fruit_trees', 'Fruit trees', buckets['fruit_trees']!),
  ];
}

List<SkillMenuListItem> _potFishingEntries(GameDatabase db) {
  final entries = <SkillMenuListItem>[];
  final seen = <String>{};
  for (final table in potFishByLocation.values) {
    for (final row in table) {
      if (!seen.add(row.itemId)) continue;
      final item = db.items.firstWhereOrNull((entry) => entry.itemId == row.itemId);
      if (item == null) continue;
      entries.add(
        SkillMenuListItem(id: item.itemId, displayName: item.displayName, level: row.fishingLevel),
      );
    }
  }
  entries.sort(_compareMenuItems);
  return entries;
}

List<SkillMenuTab> _fishingTabs(GameDatabase db) {
  return <SkillMenuTab>[
    _listTab('actions', 'Actions', _gatheringSkillActions(db, fishingSkillId)),
    _listTab('tools', 'Tools', _gatheringToolEntries(db, fishingSkillId)),
    _listTab('pot_fishing', 'Pot fishing', _potFishingEntries(db)),
  ];
}

const List<String> _cookingFishNames = <String>[
  'perch',
  'trout',
  'salmon',
  'bass',
  'shark',
  'squid',
  'catfish',
  'crawfish',
  'crab',
  'lobster',
  'eel',
  'swordfish',
  'marlin',
];

const List<String> _cookingMeatNames = <String>[
  'rabbit',
  'pheasant',
  'beef',
  'venison',
  'duck',
  'boar',
];

SkillMenuPlacement _cookingPlacement(String displayName) {
  return switch (_cookingTabId(displayName)) {
    'fish' => const SkillMenuPlacement(tabId: 'fish', tabLabel: 'Fish'),
    'meat' => const SkillMenuPlacement(tabId: 'meat', tabLabel: 'Meat'),
    'stew' => const SkillMenuPlacement(tabId: 'stew', tabLabel: 'Stew'),
    _ => const SkillMenuPlacement(tabId: 'other', tabLabel: 'Other'),
  };
}

String _cookingTabId(String displayName) {
  final lower = displayName.toLowerCase();
  if (lower.contains('stew') || lower.contains('soup')) return 'stew';
  if (_cookingFishNames.any(lower.contains)) return 'fish';
  if (_cookingMeatNames.any(lower.contains)) return 'meat';
  return 'other';
}

List<SkillMenuTab> _cookingTabs(GameDatabase db) {
  final fish = <SkillMenuListItem>[];
  final meat = <SkillMenuListItem>[];
  final stew = <SkillMenuListItem>[];
  final other = <SkillMenuListItem>[];
  for (final item in skillMenuEntries(db, cookingSkillId)) {
    switch (_cookingTabId(item.displayName)) {
      case 'fish':
        fish.add(item);
      case 'meat':
        meat.add(item);
      case 'stew':
        stew.add(item);
      default:
        other.add(item);
    }
  }
  return <SkillMenuTab>[
    _listTab('fish', 'Fish', fish),
    _listTab('meat', 'Meat', meat),
    _listTab('stew', 'Stew', stew),
    _listTab('other', 'Other', other),
  ];
}

String _alchemyOutputItemId(GameDatabase db, String displayName, String outputId) {
  if (outputId.isNotEmpty) return outputId;
  final action = db.actions.firstWhereOrNull((row) => _namesEqual(row.displayName, displayName));
  final targetId = action?.targetId;
  if (targetId != null && targetId.isNotEmpty) return targetId;
  final recipe = db.recipes.firstWhereOrNull((row) => _namesEqual(row.displayName, displayName));
  return recipe?.outputItemId ?? '';
}

bool _isAlchemyPotionOutput(GameDatabase db, String displayName, [String outputId = '']) {
  final itemId = _alchemyOutputItemId(db, displayName, outputId);
  if (itemId.isEmpty) return true;
  return alchemyRecipeUsesPotionDie(db, itemId);
}

SkillMenuPlacement _alchemyPlacement(GameDatabase db, String displayName, [String outputId = '']) {
  if (_isAlchemyPotionOutput(db, displayName, outputId)) {
    return const SkillMenuPlacement(tabId: 'potions', tabLabel: 'Potions');
  }
  return const SkillMenuPlacement(tabId: 'ingredients', tabLabel: 'Ingredients');
}

List<SkillMenuTab> _alchemyTabs(GameDatabase db) {
  final potions = <SkillMenuListItem>[];
  final ingredients = <SkillMenuListItem>[];
  for (final item in skillMenuEntries(db, alchemySkillId)) {
    final action = db.actions.firstWhereOrNull((row) => row.actionId == item.id);
    final outputId = action?.targetId ?? '';
    if (outputId.isNotEmpty && alchemyRecipeUsesPotionDie(db, outputId)) {
      potions.add(item);
    } else {
      ingredients.add(item);
    }
  }
  return <SkillMenuTab>[
    _listTab('potions', 'Potions', potions),
    _listTab('ingredients', 'Ingredients', ingredients),
  ];
}

List<SkillMenuTab> _smithingTabs(GameDatabase db) {
  final grouped = <SkillMenuListItem>[];
  final other = <SkillMenuListItem>[];
  final seenMaterials = <String>{};
  for (final project in projectsForSkill(db, smithingSkillId)) {
    final material = _smithingMaterial(project.displayName);
    if (material == null) {
      other.add(project);
      continue;
    }
    final key = '${project.level ?? ''}|$material';
    if (!seenMaterials.add(key)) continue;
    grouped.add(SkillMenuListItem(id: key, displayName: '$material items', level: project.level));
  }
  return <SkillMenuTab>[
    _listTab('basic-metal', 'Basic metal', grouped),
    _listTab('other', 'Other', other),
  ];
}

List<SkillMenuTab> _artisanryTabs(GameDatabase db) {
  final bows = <SkillMenuListItem>[];
  final jewelry = <SkillMenuListItem>[];
  final other = <SkillMenuListItem>[];
  final seenLeather = <String>{};
  for (final project in projectsForSkill(db, artisanrySkillId)) {
    final outputId = _projectOutputId(db, project.id);
    final item = _itemForOutput(db, outputId, project.displayName);
    if (_isBowItem(item)) {
      bows.add(project);
    } else if (_isJewelryItem(item)) {
      jewelry.add(project);
    } else {
      final material = _armorMaterial(item?.displayName ?? project.displayName);
      if (material != null && _isGroupedArmorMaterial(material)) {
        final key = '${project.level ?? ''}|$material';
        if (!seenLeather.add(key)) continue;
        other.add(
          SkillMenuListItem(id: key, displayName: '$material equipment', level: project.level),
        );
      } else {
        other.add(project);
      }
    }
  }
  return <SkillMenuTab>[
    _listTab('bows', 'Bows', bows),
    _listTab('jewelry', 'Jewelry', jewelry),
    _listTab('other', 'Other', other),
  ];
}

bool _isArcanaEssenceMenuItem(SkillMenuListItem item) {
  return item.id == _essenceItemId ||
      item.displayName == 'Essence' ||
      item.displayName == 'Harness essence';
}

List<SkillMenuTab> _arcanaTabs(GameDatabase db) {
  final spells = <SkillMenuListItem>[
    ...actionsForSkill(db, arcanaSkillId).where((item) => !_isArcanaEssenceMenuItem(item)),
  ];
  final weapons = <SkillMenuListItem>[];
  final enchantments = <SkillMenuListItem>[];
  for (final project in projectsForSkill(db, arcanaSkillId)) {
    if (_isArcanaEssenceMenuItem(project)) continue;
    final outputId = _projectOutputId(db, project.id);
    final item = _itemForOutput(db, outputId, project.displayName);
    if (_isSpellItem(item, project.displayName)) {
      spells.add(project);
    } else if (_isArcanaWeaponItem(item, outputId, project.displayName)) {
      weapons.add(project);
    } else if (_isEnchantmentName(project.displayName, outputId)) {
      enchantments.add(project);
    } else {
      enchantments.add(project);
    }
  }
  return <SkillMenuTab>[
    _listTab('spells', 'Spells', _dedupeByName(spells)),
    _listTab('equipment', 'Equipment', _dedupeByName(weapons)),
    _listTab('enchants', 'Enchants', _dedupeByName(enchantments)),
  ];
}

List<SkillMenuListItem> _combatGearItems(GameDatabase db, String skillId) {
  return [
    for (final item in <SkillMenuListItem>[
      ..._projectItemsWhere(db, (item, _) => _isCombatGearItem(item), <String>{
        smithingSkillId,
        artisanrySkillId,
      }),
      ..._woodenItems(db, _woodenCombatGear),
    ])
      SkillMenuListItem(
        id: item.id,
        displayName: item.displayName,
        level: _equipLevelForSkill(db, item, skillId) ?? item.level,
      ),
  ];
}

List<SkillMenuListItem> _combatEquipmentEntries(GameDatabase db) {
  final grouped = <SkillMenuListItem>[];
  final seen = <String>{};
  for (final item in _combatGearItems(db, vitalitySkillId)) {
    final material = _armorMaterial(item.displayName);
    if (material == null || !_isGroupedArmorMaterial(material)) continue;
    final key = '${item.level ?? ''}|$material';
    if (!seen.add(key)) continue;
    grouped.add(SkillMenuListItem(id: key, displayName: '$material equipment', level: item.level));
  }
  return _dedupeByName(grouped);
}

List<SkillMenuListItem> _combatWeaponEntries(GameDatabase db) {
  final grouped = <SkillMenuListItem>[];
  final seen = <String>{};
  for (final item in _combatGearItems(db, mightSkillId)) {
    if (_armorMaterial(item.displayName) != null) continue;
    final material = _weaponMaterial(item.displayName);
    if (material == null || !_isWeaponMenuMaterial(material)) continue;
    final key = '${item.level ?? ''}|$material';
    if (!seen.add(key)) continue;
    grouped.add(SkillMenuListItem(id: key, displayName: '$material weapons', level: item.level));
  }
  return _dedupeByName(grouped);
}

List<SkillMenuListItem> _combatOtherEntries(GameDatabase db, String skillId) {
  return _dedupeByName([
    for (final item in _combatGearItems(db, skillId))
      if (_isCombatOtherItem(item)) item,
  ]);
}

bool _isCombatOtherItem(SkillMenuListItem item) {
  final armor = _armorMaterial(item.displayName);
  if (armor != null) return !_isGroupedArmorMaterial(armor);
  final weapon = _weaponMaterial(item.displayName);
  if (weapon != null) return !_isWeaponMenuMaterial(weapon);
  return true;
}

List<SkillMenuListItem> _combatOtherWeaponEntries(GameDatabase db) {
  return [
    for (final item in _combatOtherEntries(db, mightSkillId))
      if (_armorMaterial(item.displayName) == null) item,
  ];
}

List<SkillMenuListItem> _combatOtherEquipmentEntries(GameDatabase db) {
  return [
    for (final item in _combatOtherEntries(db, vitalitySkillId))
      if (_armorMaterial(item.displayName) != null) item,
  ];
}

const Set<String> _metalMaterials = <String>{
  'copper',
  'tin',
  'bronze',
  'iron',
  'steel',
  'reinforced steel',
  'titanium',
  'tungsten',
  'silver',
  'gold',
  'mithril',
};

bool _isMetalMaterial(String material) {
  final lower = material.toLowerCase();
  if (_metalMaterials.contains(lower)) return true;
  return RegExp(
    r'^(copper|tin|bronze|iron|steel|titanium|tungsten|silver|gold|mithril)',
    caseSensitive: false,
  ).hasMatch(lower);
}

bool _isWeaponMenuMaterial(String material) {
  return _isMetalMaterial(material) || material.toLowerCase() == 'wooden';
}

bool _isGroupedArmorMaterial(String material) {
  final lower = material.toLowerCase();
  return _isMetalMaterial(material) || lower == 'leather' || lower == 'wooden';
}

List<SkillMenuListItem> _gatheringToolEntries(GameDatabase db, String skillId) {
  final spec = _gatheringToolSpec(skillId);
  if (spec == null) return const <SkillMenuListItem>[];
  final items = <SkillMenuListItem>[
    ..._projectItemsWhere(db, (item, name) => spec.match(item, name), null),
    ..._woodenItems(db, spec.woodenIds),
  ];
  final entries = _dedupeByName([
    for (final item in items)
      SkillMenuListItem(
        id: item.id,
        displayName: item.displayName,
        level: _equipLevelForSkill(db, item, skillId) ?? item.level,
      ),
  ]);
  if (skillId == fishingSkillId) {
    final pot = db.items.firstWhereOrNull((row) => row.itemId == fishingPotItemId);
    if (pot != null && entries.every((item) => item.id != pot.itemId)) {
      entries.add(SkillMenuListItem(id: pot.itemId, displayName: pot.displayName, level: 14));
    }
    return _dedupeByName(entries);
  }
  return entries;
}

num? _equipLevelForSkill(GameDatabase db, SkillMenuListItem entry, String skillId) {
  final item = _itemForMenuEntry(db, entry);
  if (item == null) return null;
  final equipment = db.equipment.firstWhereOrNull((row) => row.itemId == item.itemId);
  if (equipment == null || equipment.requiredSkillId != skillId) return null;
  return equipment.requiredLevel;
}

({List<String> woodenIds, bool Function(ItemRow item, String name) match})? _gatheringToolSpec(
  String skillId,
) {
  switch (skillId) {
    case miningSkillId:
      return (woodenIds: _woodenMiningTools, match: (item, _) => _itemHasTag(item, 'mining_tool'));
    case woodcuttingSkillId:
      return (woodenIds: _woodenWoodcuttingTools, match: (item, _) => _isWoodcuttingToolItem(item));
    case fishingSkillId:
      return (woodenIds: _woodenFishingTools, match: (item, _) => _isFishingToolItem(item));
    case huntingSkillId:
      return (
        woodenIds: _woodenHuntingTools,
        match: (item, _) => _itemHasTag(item, 'hunting_tool'),
      );
    default:
      return null;
  }
}

List<SkillMenuListItem> _projectItemsWhere(
  GameDatabase db,
  bool Function(ItemRow item, String name) match,
  Set<String>? skillIds,
) {
  final items = <SkillMenuListItem>[];
  for (final project in db.projects.where(isCompleteProject)) {
    final projectSkillId = jsString(project.raw['Skill ID']);
    if (skillIds != null && !skillIds.contains(projectSkillId)) continue;
    final outputId = jsString(project.raw['Output Item / Target ID']);
    if (outputId.startsWith('ENCH-')) continue;
    final item = db.items.firstWhereOrNull((row) => row.itemId == outputId);
    if (item == null || !match(item, item.displayName)) continue;
    items.add(
      SkillMenuListItem(
        id: jsString(project.raw['Project ID']),
        displayName: item.displayName,
        level: _projectLevelForSkill(project, projectSkillId),
      ),
    );
  }
  return items;
}

List<SkillMenuListItem> _woodenItems(GameDatabase db, List<String> itemIds) {
  return [
    for (final itemId in itemIds)
      if (db.items.firstWhereOrNull((row) => row.itemId == itemId) case final item?)
        SkillMenuListItem(
          id: item.itemId,
          displayName: item.displayName,
          level: _woodenToolLevel(db, itemId),
        ),
  ];
}

num _woodenToolLevel(GameDatabase db, String itemId) {
  return db.equipment.firstWhereOrNull((row) => row.itemId == itemId)?.requiredLevel ?? 1;
}

SkillMenuTab _listTab(String id, String label, List<SkillMenuListItem> entries) {
  return SkillMenuTab(
    id: id,
    label: label,
    sections: <SkillMenuSection>[SkillMenuSection(entries: entries)],
  );
}

List<SkillMenuTab> _nonEmptyTabs(List<SkillMenuTab> tabs) {
  return [
    for (final tab in tabs)
      if (tab.sections.any((section) => section.entries.isNotEmpty)) tab,
  ];
}

List<SkillMenuListItem> _dedupeByName(List<SkillMenuListItem> items) {
  final copy = [...items];
  mergeSort(copy, compare: _compareMenuItems);
  final seen = <String>{};
  return [
    for (final item in copy)
      if (seen.add(item.displayName)) item,
  ];
}

const Map<String, int> _starterMaterialRank = <String, int>{'wooden': 0, 'leather': 1, 'copper': 2};

int? _starterMaterialRankOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return null;
  return _starterMaterialRank[parts.first.toLowerCase()];
}

int _compareMenuItems(SkillMenuListItem a, SkillMenuListItem b) {
  final aLevel = a.level ?? double.infinity;
  final bLevel = b.level ?? double.infinity;
  if (aLevel != bLevel) return aLevel < bLevel ? -1 : 1;
  final aRank = _starterMaterialRankOf(a.displayName);
  final bRank = _starterMaterialRankOf(b.displayName);
  if (aRank != null && bRank != null && aRank != bRank) return aRank - bRank;
  return jsLocaleCompare(a.displayName, b.displayName);
}

String? _smithingMaterial(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return null;
  return parts.first;
}

String? _armorMaterial(String name) {
  for (final word in _combatArmorWords) {
    if (!_endsWithWord(name, word)) continue;
    if (name.length <= word.length) return null;
    final material = name.substring(0, name.length - word.length).trim();
    if (material.isEmpty) return null;
    return material;
  }
  return null;
}

String? _weaponMaterial(String name) {
  for (final word in _combatWeaponWords) {
    if (!_endsWithWord(name, word)) continue;
    if (name.length <= word.length) return null;
    final material = name.substring(0, name.length - word.length).trim();
    if (material.isEmpty) return null;
    return material;
  }
  return null;
}

bool _namesEqual(String? a, String? b) {
  return (a ?? '').trim().toLowerCase() == (b ?? '').trim().toLowerCase();
}

bool _endsWithWord(String name, String word) {
  final haystack = name.trim().toLowerCase();
  final needle = word.trim().toLowerCase();
  return haystack == needle || haystack.endsWith(' $needle');
}

Set<String> _itemTags(ItemRow? item) {
  if (item == null) return const <String>{};
  return <String>{
    for (final part in (item.functionalSourceTags ?? '').split(RegExp(r'[;,]')))
      if (part.trim().isNotEmpty) part.trim().toLowerCase(),
  };
}

bool _itemHasTag(ItemRow? item, String tag) => _itemTags(item).contains(tag.toLowerCase());

bool _isWoodcuttingToolItem(ItemRow item) {
  return _itemHasTag(item, 'woodcutting_tool') && item.subtype?.toLowerCase() != 'battleaxe';
}

bool _isFishingToolItem(ItemRow item) {
  return _itemHasTag(item, 'fishing_tool') || _itemHasTag(item, 'fishing_pot');
}

bool _isBowItem(ItemRow? item) {
  if (item == null) return false;
  return item.subtype == 'Bow' || _itemHasTag(item, 'bow_combat_xp');
}

bool _isJewelryItem(ItemRow? item) => item?.category == 'Jewelry';

bool _isCombatGearItem(ItemRow item) {
  if (item.category == 'Tool' || item.category == 'Jewelry') return false;
  if (_isWoodcuttingToolItem(item) ||
      _itemHasTag(item, 'mining_tool') ||
      _isFishingToolItem(item)) {
    return false;
  }
  final category = (item.category ?? '').toLowerCase();
  return category == 'weapon' ||
      category == 'armor' ||
      category == 'shield / off-hand' ||
      _itemHasTag(item, 'combat_weapon') ||
      _itemHasTag(item, 'combat_armor') ||
      _itemHasTag(item, 'combat_defense');
}

bool _isSpellItem(ItemRow? item, String name) {
  if (item?.category == 'Spell' || _itemHasTag(item, 'spell')) return true;
  return RegExp(r'\bspell\b', caseSensitive: false).hasMatch(name) &&
      item?.category != 'Spell Component';
}

bool _isArcanaWeaponItem(ItemRow? item, String outputId, String name) {
  if (outputId.startsWith('ENCH-')) return false;
  if (item?.itemId == _magicBolaItemId || _namesEqual(name, 'Magic bola')) return true;
  final subtype = item?.subtype?.toLowerCase() ?? '';
  if (subtype == 'staff' || subtype == 'wand') return true;
  return _itemHasTag(item, 'staff') || _itemHasTag(item, 'wand');
}

bool _isEnchantmentName(String name, String outputId) {
  return outputId.startsWith('ENCH-') ||
      name.toLowerCase().contains('enchantment') ||
      name.toLowerCase().contains('enchanted');
}

ItemRow? _itemByName(GameDatabase db, String name) {
  return db.items.firstWhereOrNull((item) => item.displayName == name) ??
      db.items.firstWhereOrNull((item) => _namesEqual(item.displayName, name));
}

ItemRow? _itemForOutput(GameDatabase db, String outputId, String displayName) {
  if (outputId.isNotEmpty) {
    final byId = db.items.firstWhereOrNull((row) => row.itemId == outputId);
    if (byId != null) return byId;
  }
  return _itemByName(db, displayName);
}

ItemRow? _itemForMenuEntry(GameDatabase db, SkillMenuListItem entry) {
  final byId = db.items.firstWhereOrNull((row) => row.itemId == entry.id);
  if (byId != null) return byId;
  final outputId = _projectOutputId(db, entry.id);
  if (outputId.isNotEmpty) {
    final byOutput = db.items.firstWhereOrNull((row) => row.itemId == outputId);
    if (byOutput != null) return byOutput;
  }
  return _itemByName(db, entry.displayName);
}

String _projectOutputId(GameDatabase db, String projectId) {
  final project = db.projects.firstWhereOrNull((row) => row.raw['Project ID'] == projectId);
  return jsString(project?.raw['Output Item / Target ID']);
}

num? _projectLevelForSkill(ProjectRow project, String skillId) {
  return projectSkillRequirements(project)
      .firstWhereOrNull((requirement) => requirement.skillId == skillId)
      ?.level;
}

int _compareSkillActions(ActionRow a, ActionRow b) {
  final aProficiency = a.raw['Proficiency Level'];
  final bProficiency = b.raw['Proficiency Level'];
  final aLevel = aProficiency is num ? aProficiency : double.infinity;
  final bLevel = bProficiency is num ? bProficiency : double.infinity;
  if (aLevel != bLevel) return aLevel < bLevel ? -1 : 1;
  return jsLocaleCompare(jsString(a.raw['Display Name']), jsString(b.raw['Display Name']));
}
