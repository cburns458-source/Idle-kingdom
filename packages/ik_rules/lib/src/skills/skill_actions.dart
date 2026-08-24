import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/requirements.dart';
import '../combat/stats.dart' show combatSkillId;
import '../js_compat.dart';
import '../npcs/knowledge.dart';
import '../production/recipes.dart';
import '../projects/projects.dart';

const String miningSkillId = 'SKL-0002';
const String fishingSkillId = 'SKL-0003';
const String harvestingSkillId = 'SKL-0004';
const String huntingSkillId = 'SKL-0005';
const String woodcuttingSkillId = 'SKL-0006';

const List<String> _woodenMiningTools = <String>['ITEM-0102'];
const List<String> _woodenWoodcuttingTools = <String>['ITEM-0100', 'ITEM-0101'];
const List<String> _woodenFishingTools = <String>['ITEM-0103'];
const List<String> _woodenCombatGear = <String>['ITEM-0124', 'ITEM-0125', 'ITEM-0145'];

const Set<String> _combatGearWords = <String>{
  'Sword',
  'Dagger',
  'Shield',
  'Helmet',
  'Chestplate',
  'Platelegs',
  'Boots',
  'Gloves',
  'Warhammer',
  'Battleaxe',
  'Bow',
  'Spear',
};

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
  return type == 'Quest Access' || type == 'Quest Flag' || type == 'Quest Active';
}

/// True when every activity that can roll this action is quest-gated.
bool actionIsQuestOnly(GameDatabase db, String actionId) {
  final activities = activitiesForAction(db, actionId);
  if (activities.isEmpty) return false;
  return activities.every((activity) {
    return requirementsForEntity(db, 'Activity', activity.activityId).any(_isQuestOnlyRequirement);
  });
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
  if (skillId == combatSkillId) {
    return <SkillMenuTab>[
      _listTab('enemies', 'Enemies', _combatEnemyEntries(db)),
      _listTab('gear', 'Weapons and equipment', _combatGearEntries(db)),
    ];
  }
  if (skillId == miningSkillId ||
      skillId == fishingSkillId ||
      skillId == harvestingSkillId ||
      skillId == huntingSkillId ||
      skillId == woodcuttingSkillId) {
    return <SkillMenuTab>[
      _listTab('actions', 'Actions', actionsForSkill(db, skillId)),
      _listTab('tools', 'Tools', _gatheringToolEntries(db, skillId)),
    ];
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
  return <SkillMenuTab>[_listTab('actions', 'Actions', skillMenuEntries(db, skillId))];
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
  for (final project in projectsForSkill(db, artisanrySkillId)) {
    final item = _itemByName(db, project.displayName);
    if (_isBowName(project.displayName)) {
      bows.add(project);
    } else if (_isJewelryItem(item, project.displayName)) {
      jewelry.add(project);
    } else {
      other.add(project);
    }
  }
  return <SkillMenuTab>[
    _listTab('bows', 'Bows', bows),
    _listTab('jewelry', 'Jewelry', jewelry),
    _listTab('other', 'Other', other),
  ];
}

List<SkillMenuTab> _arcanaTabs(GameDatabase db) {
  final spells = <SkillMenuListItem>[...actionsForSkill(db, arcanaSkillId)];
  final weapons = <SkillMenuListItem>[];
  final enchantments = <SkillMenuListItem>[];
  for (final project in projectsForSkill(db, arcanaSkillId)) {
    final outputId = _projectOutputId(db, project.id);
    if (_isSpellName(project.displayName)) {
      spells.add(project);
    } else if (_isArcanaWeaponName(project.displayName, outputId)) {
      weapons.add(project);
    } else if (_isEnchantmentName(project.displayName, outputId)) {
      enchantments.add(project);
    } else {
      enchantments.add(project);
    }
  }
  return <SkillMenuTab>[
    _listTab('spells', 'Spells', _dedupeByName(spells)),
    _listTab('weapons', 'Weapons', _dedupeByName(weapons)),
    _listTab('enchantments', 'Enchantments', _dedupeByName(enchantments)),
  ];
}

List<SkillMenuListItem> _combatEnemyEntries(GameDatabase db) {
  final items = <SkillMenuListItem>[];
  final seen = <String>{};
  for (final action in db.actions) {
    if (action.raw['Relevant Skill ID'] != combatSkillId) continue;
    if (action.raw['Status'] == 'Needs Data') continue;
    if (actionIsQuestOnly(db, action.actionId)) continue;
    final enemy = _enemyForCombatAction(db, action);
    if (enemy == null) continue;
    final name = enemy.displayName.trim();
    if (name.isEmpty || !seen.add(name)) continue;
    items.add(SkillMenuListItem(id: action.actionId, displayName: name, level: enemy.combatLevel));
  }
  return _dedupeByName(items);
}

List<SkillMenuListItem> _combatGearEntries(GameDatabase db) {
  final items = <SkillMenuListItem>[
    ..._projectItemsWhere(db, (item, _) => _isCombatGearItem(item), <String>{
      smithingSkillId,
      artisanrySkillId,
    }),
    ..._woodenItems(db, _woodenCombatGear),
  ];
  return _dedupeByName(items);
}

List<SkillMenuListItem> _gatheringToolEntries(GameDatabase db, String skillId) {
  final spec = _gatheringToolSpec(skillId);
  if (spec == null) return const <SkillMenuListItem>[];
  final items = <SkillMenuListItem>[
    ..._projectItemsWhere(db, (item, name) => spec.match(item, name), null),
    ..._woodenItems(db, spec.woodenIds),
  ];
  return _dedupeByName(items);
}

({List<String> woodenIds, bool Function(ItemRow item, String name) match})? _gatheringToolSpec(
  String skillId,
) {
  switch (skillId) {
    case miningSkillId:
      return (woodenIds: _woodenMiningTools, match: (item, name) => _endsWithWord(name, 'Pickaxe'));
    case woodcuttingSkillId:
      return (
        woodenIds: _woodenWoodcuttingTools,
        match: (item, name) => _isWoodcuttingToolName(name),
      );
    case fishingSkillId:
      return (woodenIds: _woodenFishingTools, match: (item, name) => _isFishingToolName(name));
    case huntingSkillId:
      return (woodenIds: const <String>[], match: (item, name) => _isHuntingToolName(name));
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
        SkillMenuListItem(id: item.itemId, displayName: item.displayName, level: 1),
  ];
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

int _compareMenuItems(SkillMenuListItem a, SkillMenuListItem b) {
  final aLevel = a.level ?? double.infinity;
  final bLevel = b.level ?? double.infinity;
  if (aLevel != bLevel) return aLevel < bLevel ? -1 : 1;
  return jsLocaleCompare(a.displayName, b.displayName);
}

String? _smithingMaterial(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return null;
  return parts.first;
}

bool _endsWithWord(String name, String word) {
  return name == word || name.endsWith(' $word');
}

bool _isWoodcuttingToolName(String name) {
  if (_endsWithWord(name, 'Battleaxe')) return false;
  return _endsWithWord(name, 'Axe') || _endsWithWord(name, 'Hatchet');
}

bool _isFishingToolName(String name) {
  return name.contains('Fishing Rod') ||
      _endsWithWord(name, 'Harpoon') ||
      _endsWithWord(name, 'Net');
}

bool _isHuntingToolName(String name) {
  return _endsWithWord(name, 'Bow') || _endsWithWord(name, 'Spear');
}

bool _isBowName(String name) => _endsWithWord(name, 'Bow');

bool _isJewelryItem(ItemRow? item, String name) {
  if (item?.category == 'Jewelry') return true;
  return name.contains('Necklace') || name.contains('Ring');
}

bool _isCombatGearItem(ItemRow item) {
  if (item.category == 'Tool' || item.category == 'Jewelry') return false;
  if (item.displayName.contains('Necklace') ||
      item.displayName.contains('Ring') ||
      item.displayName.contains('Backpack')) {
    return false;
  }
  if (_isWoodcuttingToolName(item.displayName) ||
      _endsWithWord(item.displayName, 'Pickaxe') ||
      _isFishingToolName(item.displayName)) {
    return false;
  }
  return _combatGearWords.any((word) => _endsWithWord(item.displayName, word));
}

bool _isSpellName(String name) => name.contains('Spell');

bool _isArcanaWeaponName(String name, String outputId) {
  if (outputId.startsWith('ENCH-')) return false;
  return RegExp(r'staff of\b', caseSensitive: false).hasMatch(name) ||
      RegExp(r'\bstaff\b', caseSensitive: false).hasMatch(name);
}

bool _isEnchantmentName(String name, String outputId) {
  return outputId.startsWith('ENCH-') || name.contains('Enchantment') || name.contains('Enchanted');
}

ItemRow? _itemByName(GameDatabase db, String name) {
  return db.items.firstWhereOrNull((item) => item.displayName == name);
}

String _projectOutputId(GameDatabase db, String projectId) {
  final project = db.projects.firstWhereOrNull((row) => row.raw['Project ID'] == projectId);
  return jsString(project?.raw['Output Item / Target ID']);
}

EnemyRow? _enemyForCombatAction(GameDatabase db, ActionRow action) {
  if (action.category != 'Combat') return null;
  final targetId = action.targetId;
  if (targetId == null || targetId.isEmpty) return null;
  return db.enemies.firstWhereOrNull((row) => row.raw['Enemy ID'] == targetId);
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
