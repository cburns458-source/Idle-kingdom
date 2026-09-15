import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../equipment/tooltips.dart';
import '../inventory/sort.dart';
import '../js_compat.dart';
import '../production/recipes.dart';
import '../projects/projects.dart';
import '../save/generated/save_models.dart';
import '../shops/shops.dart';
import '../spells/spells.dart';

/// How an item enters the world. New kinds can be appended without rewriting pages.
enum CodexObtainKind { action, enemy, shop, starter, quest }

const String _goldenSpudItemId = 'ITEM-0026';
const String _chefHatItemId = 'ITEM-0165';
const String _hideFromCodexActionId = 'ACN-0036';
const String _miningSkillId = 'SKL-0002';
const Set<String> _oreGemTableIds = {'RWT-0058', 'RWT-0059', 'RWT-0060'};

bool _notesHideFromCodex(Object? notes) {
  final text = notes is String ? notes : '';
  return RegExp(r'HideFromCodex|MysteryDrop', caseSensitive: false).hasMatch(text);
}

bool _hideActionFromCodex(ActionRow action) {
  if (action.actionId == _hideFromCodexActionId || _notesHideFromCodex(action.notes)) {
    return true;
  }
  return action.category == 'Gathering' && action.status == 'Needs Data';
}

String? _combatEnemyId(ActionRow action) {
  if (action.category != 'Combat') return null;
  final targetId = action.targetId;
  if (action.targetType == 'Enemy' && targetId != null && targetId.isNotEmpty) return targetId;
  return null;
}

/// Quest rewards in Obtained from: non-cosmetic gear/tools only (Tool / Weapon / Armor).
/// Category Cosmetic is omitted; Chef's Hat ([_chefHatItemId]) is also omitted as vanity headwear.
bool _includeQuestRewardAsObtainSource(String? category, String itemId) {
  if (itemId == _chefHatItemId) return false;
  if (category == 'Cosmetic') return false;
  return category == 'Tool' || category == 'Weapon' || category == 'Armor';
}

/// Pets, cosmetics, and quest-key items stay in the database; they stay out of the Codex.
bool includeInCodexCatalog({String? category, String? subtype}) {
  if (subtype == 'Pet') return false;
  if (category == 'Cosmetic' || category == 'Quest') return false;
  return true;
}

/// A clickable item mention on a Codex page.
class CodexItemRef {
  const CodexItemRef({
    required this.itemId,
    required this.displayName,
    this.minQuantity,
    this.maxQuantity,
    this.weight,
    this.dropRatePercent,
  });

  final String itemId;
  final String displayName;
  final num? minQuantity;
  final num? maxQuantity;
  final num? weight;

  /// Weight share of the reward table, as a percent (0–100).
  final num? dropRatePercent;

  Map<String, Object?> toJson() => <String, Object?>{
    'itemId': itemId,
    'displayName': displayName,
    if (minQuantity != null) 'minQuantity': minQuantity,
    if (maxQuantity != null) 'maxQuantity': maxQuantity,
    if (weight != null) 'weight': weight,
    if (dropRatePercent != null) 'dropRatePercent': dropRatePercent,
  };
}

/// A clickable enemy mention on a Codex page.
class CodexEnemyRef {
  const CodexEnemyRef({required this.enemyId, required this.displayName});

  final String enemyId;
  final String displayName;

  Map<String, Object?> toJson() => <String, Object?>{
    'enemyId': enemyId,
    'displayName': displayName,
  };
}

/// A location an action or enemy uses.
class CodexLocationRef {
  const CodexLocationRef({required this.locationId, required this.displayName});

  final String locationId;
  final String displayName;

  Map<String, Object?> toJson() => <String, Object?>{
    'locationId': locationId,
    'displayName': displayName,
  };
}

/// One obtain line on an item page.
class CodexObtainSource {
  const CodexObtainSource({
    required this.kind,
    required this.title,
    this.detail,
    this.actionId,
    this.enemyId,
    this.shopId,
    this.questId,
    this.locations = const <CodexLocationRef>[],
    this.dropChance,
    this.minQuantity,
    this.maxQuantity,
  });

  final CodexObtainKind kind;
  final String title;
  final String? detail;
  final String? actionId;
  final String? enemyId;
  final String? shopId;
  final String? questId;
  final List<CodexLocationRef> locations;
  final num? dropChance;
  final num? minQuantity;
  final num? maxQuantity;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'title': title,
    if (detail != null) 'detail': detail,
    if (actionId != null) 'actionId': actionId,
    if (enemyId != null) 'enemyId': enemyId,
    if (shopId != null) 'shopId': shopId,
    if (questId != null) 'questId': questId,
    if (locations.isNotEmpty) 'locations': [for (final row in locations) row.toJson()],
    if (dropChance != null) 'dropChance': dropChance,
    if (minQuantity != null) 'minQuantity': minQuantity,
    if (maxQuantity != null) 'maxQuantity': maxQuantity,
  };
}

/// A recipe or project that produces or consumes items.
class CodexCraft {
  const CodexCraft({
    required this.id,
    required this.isProject,
    required this.displayName,
    required this.skillId,
    required this.skillName,
    this.level,
    this.facilityName,
    required this.output,
    required this.ingredients,
  });

  final String id;
  final bool isProject;
  final String displayName;
  final String skillId;
  final String skillName;
  final num? level;
  final String? facilityName;
  final CodexItemRef output;
  final List<CodexItemRef> ingredients;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'isProject': isProject,
    'displayName': displayName,
    'skillId': skillId,
    'skillName': skillName,
    if (level != null) 'level': level,
    if (facilityName != null) 'facilityName': facilityName,
    'output': output.toJson(),
    'ingredients': [for (final row in ingredients) row.toJson()],
  };
}

/// Everything the Codex shows for one item.
class CodexItemEntry {
  const CodexItemEntry({
    required this.itemId,
    required this.displayName,
    this.category,
    this.subtype,
    this.description,
    required this.group,
    required this.groupLabel,
    this.statLines = const <String>[],
    this.obtainedFrom = const <CodexObtainSource>[],
    this.craftedBy = const <CodexCraft>[],
    this.usedIn = const <CodexCraft>[],
  });

  final String itemId;
  final String displayName;
  final String? category;
  final String? subtype;
  final String? description;
  final int group;
  final String groupLabel;
  final List<String> statLines;
  final List<CodexObtainSource> obtainedFrom;
  final List<CodexCraft> craftedBy;
  final List<CodexCraft> usedIn;

  Map<String, Object?> toJson() => <String, Object?>{
    'itemId': itemId,
    'displayName': displayName,
    if (category != null) 'category': category,
    if (subtype != null) 'subtype': subtype,
    if (description != null) 'description': description,
    'group': group,
    'groupLabel': groupLabel,
    'statLines': statLines,
    'obtainedFrom': [for (final row in obtainedFrom) row.toJson()],
    'craftedBy': [for (final row in craftedBy) row.toJson()],
    'usedIn': [for (final row in usedIn) row.toJson()],
  };
}

/// Everything the Codex shows for one enemy.
class CodexEnemyEntry {
  const CodexEnemyEntry({
    required this.enemyId,
    required this.displayName,
    this.combatLevel,
    required this.maximumHp,
    required this.minDamage,
    required this.maxDamage,
    this.combatXp,
    this.xpSkillLabel = 'Combat',
    this.minimumGold,
    this.maximumGold,
    this.dropChance,
    this.locations = const <CodexLocationRef>[],
    this.drops = const <CodexItemRef>[],
  });

  final String enemyId;
  final String displayName;
  final num? combatLevel;
  final num maximumHp;
  final num minDamage;
  final num maxDamage;
  final num? combatXp;

  /// Skill name shown beside XP (Fishing for Mother Squid / Squidlings).
  final String xpSkillLabel;
  final num? minimumGold;
  final num? maximumGold;
  final num? dropChance;
  final List<CodexLocationRef> locations;
  final List<CodexItemRef> drops;

  Map<String, Object?> toJson() => <String, Object?>{
    'enemyId': enemyId,
    'displayName': displayName,
    if (combatLevel != null) 'combatLevel': combatLevel,
    'maximumHp': maximumHp,
    'minDamage': minDamage,
    'maxDamage': maxDamage,
    if (combatXp != null) 'combatXp': combatXp,
    'xpSkillLabel': xpSkillLabel,
    if (minimumGold != null) 'minimumGold': minimumGold,
    if (maximumGold != null) 'maximumGold': maximumGold,
    if (dropChance != null) 'dropChance': dropChance,
    'locations': [for (final row in locations) row.toJson()],
    'drops': [for (final row in drops) row.toJson()],
  };
}

/// One reward table on an action page (merged drop pool, ore gems, and so on).
class CodexActionDropTable {
  const CodexActionDropTable({
    required this.label,
    required this.tableId,
    this.dropChance,
    this.drops = const <CodexItemRef>[],
  });

  final String label;
  final String tableId;
  final num? dropChance;
  final List<CodexItemRef> drops;

  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    'tableId': tableId,
    if (dropChance != null) 'dropChance': dropChance,
    'drops': [for (final row in drops) row.toJson()],
  };
}

/// Everything the Codex shows for one action.
class CodexActionEntry {
  const CodexActionEntry({
    required this.actionId,
    required this.displayName,
    this.category,
    this.skillId,
    this.skillName,
    this.level,
    this.locations = const <CodexLocationRef>[],
    this.target,
    this.tables = const <CodexActionDropTable>[],
  });

  final String actionId;
  final String displayName;
  final String? category;
  final String? skillId;
  final String? skillName;
  final num? level;
  final List<CodexLocationRef> locations;
  final CodexItemRef? target;
  final List<CodexActionDropTable> tables;

  Map<String, Object?> toJson() => <String, Object?>{
    'actionId': actionId,
    'displayName': displayName,
    if (category != null) 'category': category,
    if (skillId != null) 'skillId': skillId,
    if (skillName != null) 'skillName': skillName,
    if (level != null) 'level': level,
    'locations': [for (final row in locations) row.toJson()],
    if (target != null) 'target': target!.toJson(),
    'tables': [for (final row in tables) row.toJson()],
  };
}

/// Reverse indexes over whatever [GameDatabase] is passed in.
///
/// Built from tables, not hardcoded ids, so new items, recipes, and enemies
/// appear the next time the database is loaded.
class CodexIndex {
  CodexIndex(this.db) : _sorter = InventorySorter(db) {
    _build();
  }

  final GameDatabase db;
  final InventorySorter _sorter;

  final Map<String, CodexItemEntry> _items = <String, CodexItemEntry>{};
  final Map<String, CodexEnemyEntry> _enemies = <String, CodexEnemyEntry>{};
  final Map<String, CodexActionEntry> _actions = <String, CodexActionEntry>{};
  final List<String> _itemOrder = <String>[];
  final List<String> _enemyOrder = <String>[];
  final List<String> _actionOrder = <String>[];

  List<CodexItemEntry> get items => [for (final id in _itemOrder) _items[id]!];

  List<CodexEnemyEntry> get enemies => [for (final id in _enemyOrder) _enemies[id]!];

  List<CodexActionEntry> get actions => [for (final id in _actionOrder) _actions[id]!];

  CodexItemEntry? item(String itemId) => _items[itemId];

  CodexEnemyEntry? enemy(String enemyId) => _enemies[enemyId];

  CodexActionEntry? action(String actionId) => _actions[actionId];

  /// Filter chips plus the same name search the bag uses.
  List<CodexItemEntry> itemsMatching({int? group, String query = ''}) {
    final needle = query.trim();
    return [
      for (final id in _itemOrder)
        if ((group == null || _items[id]!.group == group) && _sorter.itemMatchesName(id, needle))
          _items[id]!,
    ];
  }

  List<CodexEnemyEntry> enemiesMatching([String query = '']) {
    final needle = query.trim().toLowerCase();
    return [
      for (final id in _enemyOrder)
        if (needle.isEmpty || _enemies[id]!.displayName.toLowerCase().contains(needle))
          _enemies[id]!,
    ];
  }

  List<CodexActionEntry> actionsMatching([String query = '']) {
    final needle = query.trim().toLowerCase();
    return [
      for (final id in _actionOrder)
        if (needle.isEmpty ||
            _actions[id]!.displayName.toLowerCase().contains(needle) ||
            (_actions[id]!.skillName ?? '').toLowerCase().contains(needle))
          _actions[id]!,
    ];
  }

  void _build() {
    final names = <String, String>{for (final item in db.items) item.itemId: item.displayName};
    final enemyNames = <String, String>{
      for (final enemy in db.enemies) enemy.enemyId: enemy.displayName,
    };
    final skills = <String, String>{
      for (final skill in db.skills) skill.skillId: skill.displayName,
    };
    final locations = <String, String>{
      for (final location in db.locations) location.locationId: location.displayName,
    };
    final facilities = <String, FacilityRow>{
      for (final facility in db.facilities) facility.facilityId: facility,
    };
    final actionLocations = _actionLocations(locations);
    final tableItems = _rewardItems(names);

    final obtained = <String, List<CodexObtainSource>>{};
    final craftedBy = <String, List<CodexCraft>>{};
    final usedIn = <String, List<CodexCraft>>{};

    void addObtain(String? itemId, CodexObtainSource source) {
      if (itemId == null || itemId.isEmpty || !names.containsKey(itemId)) {
        return;
      }
      if (itemId == _goldenSpudItemId) {
        return;
      }
      final list = obtained.putIfAbsent(itemId, () => <CodexObtainSource>[]);
      final key = [
        source.kind.name,
        source.actionId,
        source.enemyId,
        source.shopId,
        source.questId,
        source.title,
      ].join('|');
      if (list.any((row) {
        final existing = [
          row.kind.name,
          row.actionId,
          row.enemyId,
          row.shopId,
          row.questId,
          row.title,
        ].join('|');
        return existing == key;
      })) {
        return;
      }
      list.add(source);
    }

    void addCraft(CodexCraft craft) {
      if (names.containsKey(craft.output.itemId)) {
        craftedBy.putIfAbsent(craft.output.itemId, () => <CodexCraft>[]).add(craft);
      }
      for (final ingredient in craft.ingredients) {
        if (names.containsKey(ingredient.itemId)) {
          usedIn.putIfAbsent(ingredient.itemId, () => <CodexCraft>[]).add(craft);
        }
      }
    }

    for (final enemy in db.enemies) {
      final tableId = enemy.rewardTableId;
      if (tableId == null || tableId.isEmpty) continue;
      final locs = _enemyLocations(enemy, actionLocations, locations);
      for (final drop in tableItems[tableId] ?? const <CodexItemRef>[]) {
        addObtain(
          drop.itemId,
          CodexObtainSource(
            kind: CodexObtainKind.enemy,
            title: enemy.displayName,
            enemyId: enemy.enemyId,
            locations: locs,
            dropChance: enemy.dropChance,
            minQuantity: drop.minQuantity,
            maxQuantity: drop.maxQuantity,
          ),
        );
      }
    }

    for (final action in db.actions) {
      if (action.category == 'Standard Production') continue;
      if (_hideActionFromCodex(action)) continue;
      final locs = actionLocations[action.actionId] ?? const <CodexLocationRef>[];
      final skillName = skills[action.relevantSkillId];
      final level = action.proficiencyLevel;
      final detailParts = <String>[
        if (skillName != null && skillName.isNotEmpty) skillName,
        if (level != null) 'Level ${jsNumberToString(level)}',
      ];
      final detail = detailParts.isEmpty ? null : detailParts.join(' · ');
      final enemyId = _combatEnemyId(action);
      final enemyTitle = enemyId == null ? null : enemyNames[enemyId];
      CodexObtainSource obtainFromAction({num? dropChance, num? minQuantity, num? maxQuantity}) {
        if (enemyId != null) {
          return CodexObtainSource(
            kind: CodexObtainKind.enemy,
            title: enemyTitle ?? action.displayName,
            enemyId: enemyId,
            locations: locs,
            dropChance: dropChance,
            minQuantity: minQuantity,
            maxQuantity: maxQuantity,
          );
        }
        return CodexObtainSource(
          kind: CodexObtainKind.action,
          title: action.displayName,
          detail: detail,
          actionId: action.actionId,
          locations: locs,
          dropChance: dropChance,
          minQuantity: minQuantity,
          maxQuantity: maxQuantity,
        );
      }

      if (action.targetType == 'Item' && action.targetId != null) {
        addObtain(action.targetId, obtainFromAction());
      }

      // Gathering, combat, and other action reward tables (including secondary combat loot).
      for (final table in _actionTables(action)) {
        for (final drop in tableItems[table.id] ?? const <CodexItemRef>[]) {
          addObtain(
            drop.itemId,
            obtainFromAction(
              dropChance: table.chance,
              minQuantity: drop.minQuantity,
              maxQuantity: drop.maxQuantity,
            ),
          );
        }
      }
    }

    for (final recipe in db.recipes) {
      if (!recipe.outputItemId.startsWith('ITEM-')) continue;
      addCraft(
        CodexCraft(
          id: recipe.recipeId,
          isProject: false,
          displayName: recipe.displayName,
          skillId: recipe.skillId,
          skillName: skills[recipe.skillId] ?? recipe.skillId,
          level: recipe.proficiencyLevel,
          facilityName: facilities[recipe.facilityId]?.displayName,
          output: CodexItemRef(
            itemId: recipe.outputItemId,
            displayName: names[recipe.outputItemId] ?? recipe.outputItemId,
            minQuantity: recipe.outputQuantity,
            maxQuantity: recipe.outputQuantity,
          ),
          ingredients: [
            for (final ingredient in recipeIngredients(recipe))
              CodexItemRef(
                itemId: ingredient.itemId,
                displayName: names[ingredient.itemId] ?? ingredient.itemId,
                minQuantity: ingredient.quantity,
                maxQuantity: ingredient.quantity,
              ),
          ],
        ),
      );
    }

    for (final project in db.projects) {
      final outputId = project.outputItemTargetId;
      if (!outputId.startsWith('ITEM-')) continue;
      addCraft(
        CodexCraft(
          id: project.projectId,
          isProject: true,
          displayName: project.displayName,
          skillId: project.skillId,
          skillName: skills[project.skillId] ?? project.skillId,
          level: project.requiredSkill1Level,
          facilityName: facilities[project.facilityId]?.displayName,
          output: CodexItemRef(
            itemId: outputId,
            displayName: names[outputId] ?? outputId,
            minQuantity: project.outputQuantity,
            maxQuantity: project.outputQuantity,
          ),
          ingredients: [
            for (final input in projectInputs(project))
              CodexItemRef(
                itemId: input.itemId,
                displayName: names[input.itemId] ?? input.itemId,
                minQuantity: input.quantity,
                maxQuantity: input.quantity,
              ),
          ],
        ),
      );
    }

    for (final shop in db.shops) {
      for (final stock in shopStockEntries(shop)) {
        addObtain(
          stock.itemId,
          CodexObtainSource(
            kind: CodexObtainKind.shop,
            title: shop.displayName,
            shopId: shop.shopId,
            locations: [
              if (locations[shop.locationId] != null)
                CodexLocationRef(
                  locationId: shop.locationId,
                  displayName: locations[shop.locationId]!,
                ),
            ],
          ),
        );
      }
    }

    // Quest rewards: non-cosmetic gear/tools only (see _includeQuestRewardAsObtainSource).
    final itemCategory = <String, String?>{for (final item in db.items) item.itemId: item.category};
    for (final quest in db.quests) {
      final rewardId = quest['Reward Item ID'];
      if (rewardId is! String || rewardId.isEmpty) continue;
      if (!_includeQuestRewardAsObtainSource(itemCategory[rewardId], rewardId)) continue;
      final qty = quest['Reward Item Quantity'];
      final qtyNum = qty is num ? qty : null;
      final title = quest['Display Name'];
      final questId = quest['Quest ID'];
      addObtain(
        rewardId,
        CodexObtainSource(
          kind: CodexObtainKind.quest,
          title: title is String ? title : '${questId ?? 'Quest'}',
          questId: questId is String ? questId : null,
          minQuantity: qtyNum,
          maxQuantity: qtyNum,
        ),
      );
    }

    for (final starter in db.raceStartingItems) {
      final race = db.races.firstWhereOrNull((row) => row.raceId == starter.raceId);
      addObtain(
        starter.itemId,
        CodexObtainSource(
          kind: CodexObtainKind.starter,
          title: race == null ? 'Starting kit' : '${race.displayName} starting kit',
          minQuantity: starter.quantity,
          maxQuantity: starter.quantity,
        ),
      );
    }

    final itemIds = [for (final item in db.items) item.itemId];
    itemIds.sort((a, b) {
      return _sorter.compareGrouped(
        InventoryStack(itemId: a, quantity: 1),
        InventoryStack(itemId: b, quantity: 1),
      );
    });
    for (final itemId in itemIds) {
      final item = db.items.firstWhere((row) => row.itemId == itemId);
      final group = _sorter.groupOf(itemId);
      if (includeInCodexCatalog(category: item.category, subtype: item.subtype)) {
        _itemOrder.add(itemId);
      }
      _items[itemId] = CodexItemEntry(
        itemId: itemId,
        displayName: item.displayName,
        category: item.category,
        subtype: item.subtype,
        description: item.description,
        group: group,
        groupLabel: inventoryGroupLabel(group),
        statLines: [
          ...equipmentTooltipStatLines(equipmentForItemId(db, itemId), db),
          if (isSpellItem(db, itemId)) ...spellTooltipLines(db, item, itemId),
        ],
        obtainedFrom: obtained[itemId] ?? const <CodexObtainSource>[],
        craftedBy: craftedBy[itemId] ?? const <CodexCraft>[],
        usedIn: usedIn[itemId] ?? const <CodexCraft>[],
      );
    }

    final fishingEnemyIds = <String>{};
    for (final enemy in db.enemies) {
      final notes = enemy.raw['Notes'];
      final text = notes is String ? notes : '';
      if (RegExp(r'damage_mode:fishing', caseSensitive: false).hasMatch(text)) {
        fishingEnemyIds.add(enemy.enemyId);
        final squidling = RegExp(
          r'squidling_enemy:([A-Z0-9-]+)',
          caseSensitive: false,
        ).firstMatch(text)?.group(1);
        if (squidling != null) fishingEnemyIds.add(squidling);
      }
      if (RegExp(r'squidling', caseSensitive: false).hasMatch(enemy.displayName) ||
          RegExp(r'squidling', caseSensitive: false).hasMatch(text)) {
        fishingEnemyIds.add(enemy.enemyId);
      }
    }

    final enemyRows = [...db.enemies];
    enemyRows.sort((a, b) {
      final level = jsNumber(a.combatLevel ?? 0).compareTo(jsNumber(b.combatLevel ?? 0));
      if (level != 0) return level;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    for (final enemy in enemyRows) {
      final tableId = enemy.rewardTableId;
      final drops = tableId == null
          ? const <CodexItemRef>[]
          : [
              for (final drop in tableItems[tableId] ?? const <CodexItemRef>[])
                if (drop.itemId != _goldenSpudItemId &&
                    includeInCodexCatalog(
                      category: _items[drop.itemId]?.category,
                      subtype: _items[drop.itemId]?.subtype,
                    ))
                  drop,
            ];
      _enemyOrder.add(enemy.enemyId);
      _enemies[enemy.enemyId] = CodexEnemyEntry(
        enemyId: enemy.enemyId,
        displayName: enemy.displayName,
        combatLevel: enemy.combatLevel,
        maximumHp: enemy.maximumHp,
        minDamage: enemy.minDamage,
        maxDamage: enemy.maxDamage,
        combatXp: enemy.combatXp,
        xpSkillLabel: fishingEnemyIds.contains(enemy.enemyId) ? 'Fishing' : 'Combat',
        minimumGold: enemy.minimumGold,
        maximumGold: enemy.maximumGold,
        dropChance: enemy.dropChance,
        locations: _enemyLocations(enemy, actionLocations, locations),
        drops: _withDropRates(drops),
      );
    }

    final actionRows = [
      for (final action in db.actions)
        if (action.category == 'Gathering' && !_hideActionFromCodex(action)) action,
    ];
    actionRows.sort((a, b) {
      final skillA = a.relevantSkillId;
      final skillB = b.relevantSkillId;
      final skill = skillA.compareTo(skillB);
      if (skill != 0) return skill;
      final level = jsNumber(a.proficiencyLevel ?? 0).compareTo(jsNumber(b.proficiencyLevel ?? 0));
      if (level != 0) return level;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    for (final action in actionRows) {
      final tables = _catalogActionTables(action, tableItems, _items);
      final targetId = action.targetType == 'Item' ? action.targetId : null;
      final targetItem = targetId == null ? null : _items[targetId];
      _actionOrder.add(action.actionId);
      _actions[action.actionId] = CodexActionEntry(
        actionId: action.actionId,
        displayName: action.displayName,
        category: action.category,
        skillId: action.relevantSkillId,
        skillName: skills[action.relevantSkillId],
        level: action.proficiencyLevel,
        locations: actionLocations[action.actionId] ?? const <CodexLocationRef>[],
        target:
            targetId != null &&
                targetItem != null &&
                includeInCodexCatalog(category: targetItem.category, subtype: targetItem.subtype)
            ? CodexItemRef(itemId: targetId, displayName: targetItem.displayName)
            : null,
        tables: tables,
      );
    }
  }

  Map<String, List<CodexLocationRef>> _actionLocations(Map<String, String> locations) {
    final poolActions = <String, List<String>>{};
    for (final entry in db.poolEntries) {
      poolActions.putIfAbsent(entry.poolId, () => <String>[]).add(entry.actionId);
    }
    final out = <String, List<CodexLocationRef>>{};
    for (final activity in db.activities) {
      final poolId = activity.poolId;
      if (poolId == null || poolId.isEmpty) continue;
      final locationName = locations[activity.locationId];
      if (locationName == null) continue;
      final loc = CodexLocationRef(locationId: activity.locationId, displayName: locationName);
      for (final actionId in poolActions[poolId] ?? const <String>[]) {
        final list = out.putIfAbsent(actionId, () => <CodexLocationRef>[]);
        if (list.every((row) => row.locationId != loc.locationId)) {
          list.add(loc);
        }
      }
    }
    return out;
  }

  Map<String, List<CodexItemRef>> _rewardItems(Map<String, String> names) {
    final out = <String, List<CodexItemRef>>{};
    for (final entry in db.rewardEntries) {
      if (entry.rewardType != 'Item') continue;
      final itemId = entry.rewardIdValue;
      if (itemId == null || itemId.isEmpty || !names.containsKey(itemId)) {
        continue;
      }
      final list = out.putIfAbsent(entry.rewardTableId, () => <CodexItemRef>[]);
      final existingIndex = list.indexWhere((row) => row.itemId == itemId);
      if (existingIndex >= 0) {
        final current = list[existingIndex];
        list[existingIndex] = CodexItemRef(
          itemId: itemId,
          displayName: names[itemId]!,
          minQuantity: _minNum(current.minQuantity, entry.minimumQuantity),
          maxQuantity: _maxNum(current.maxQuantity, entry.maximumQuantity),
          weight: (current.weight ?? 0) + (entry.weight ?? 0),
        );
      } else {
        list.add(
          CodexItemRef(
            itemId: itemId,
            displayName: names[itemId]!,
            minQuantity: entry.minimumQuantity,
            maxQuantity: entry.maximumQuantity,
            weight: entry.weight,
          ),
        );
      }
    }
    return out;
  }

  List<CodexLocationRef> _enemyLocations(
    EnemyRow enemy,
    Map<String, List<CodexLocationRef>> actionLocations,
    Map<String, String> locations,
  ) {
    final seen = <String>{};
    final out = <CodexLocationRef>[];
    void add(CodexLocationRef loc) {
      if (seen.add(loc.locationId)) out.add(loc);
    }

    for (final action in db.actions) {
      if (action.category != 'Combat' || action.targetId != enemy.enemyId) continue;
      for (final loc in actionLocations[action.actionId] ?? const <CodexLocationRef>[]) {
        add(loc);
      }
    }
    final homeId = enemy.locationId;
    if (homeId != null && homeId.isNotEmpty && locations[homeId] != null) {
      add(CodexLocationRef(locationId: homeId, displayName: locations[homeId]!));
    }
    return out;
  }
}

class _TableChance {
  const _TableChance(this.id, this.chance, this.label);
  final String id;
  final num? chance;
  final String label;
}

List<_TableChance> _actionTables(ActionRow action) {
  return [
    if (action.rewardTableId != null && action.rewardTableId!.isNotEmpty)
      _TableChance(action.rewardTableId!, action.dropChance, 'Primary'),
    if (action.secondaryRewardTableId != null && action.secondaryRewardTableId!.isNotEmpty)
      _TableChance(action.secondaryRewardTableId!, action.secondaryDropChance, 'Secondary'),
    if (action.tertiaryRewardTableId != null && action.tertiaryRewardTableId!.isNotEmpty)
      _TableChance(action.tertiaryRewardTableId!, action.tertiaryDropChance, 'Tertiary'),
  ];
}

bool _isOreGemTable(ActionRow action, String tableId) {
  return action.relevantSkillId == _miningSkillId && _oreGemTableIds.contains(tableId);
}

List<CodexActionDropTable> _catalogActionTables(
  ActionRow action,
  Map<String, List<CodexItemRef>> tableItems,
  Map<String, CodexItemEntry> items,
) {
  bool keepDrop(CodexItemRef drop) {
    if (drop.itemId == _goldenSpudItemId) return false;
    final item = items[drop.itemId];
    if (item == null) return false;
    return includeInCodexCatalog(category: item.category, subtype: item.subtype);
  }

  final merged = <CodexItemRef>[];
  final gems = <CodexActionDropTable>[];
  String? mergedTableId;
  for (final table in _actionTables(action)) {
    final drops = [
      for (final drop in tableItems[table.id] ?? const <CodexItemRef>[])
        if (keepDrop(drop)) drop,
    ];
    if (drops.isEmpty) continue;
    if (_isOreGemTable(action, table.id)) {
      gems.add(
        CodexActionDropTable(
          label: 'Gems',
          tableId: table.id,
          dropChance: table.chance,
          drops: _withEffectiveDropRates(drops, table.chance),
        ),
      );
      continue;
    }
    mergedTableId ??= table.id;
    merged.addAll(_withEffectiveDropRates(drops, table.chance));
  }
  return [
    if (merged.isNotEmpty && mergedTableId != null)
      CodexActionDropTable(label: 'Drops', tableId: mergedTableId, drops: merged),
    ...gems,
  ];
}

List<CodexItemRef> _withEffectiveDropRates(List<CodexItemRef> drops, num? tableChance) {
  final totalWeight = drops.fold<num>(0, (sum, drop) => sum + (drop.weight ?? 0));
  final chance = tableChance ?? 100;
  return [
    for (final drop in drops)
      CodexItemRef(
        itemId: drop.itemId,
        displayName: drop.displayName,
        minQuantity: drop.minQuantity,
        maxQuantity: drop.maxQuantity,
        weight: drop.weight,
        dropRatePercent: drop.weight != null && totalWeight > 0
            ? (drop.weight! / totalWeight) * chance
            : null,
      ),
  ];
}

List<CodexItemRef> _withDropRates(List<CodexItemRef> drops) {
  final totalWeight = drops.fold<num>(0, (sum, drop) => sum + (drop.weight ?? 0));
  return [
    for (final drop in drops)
      CodexItemRef(
        itemId: drop.itemId,
        displayName: drop.displayName,
        minQuantity: drop.minQuantity,
        maxQuantity: drop.maxQuantity,
        weight: drop.weight,
        dropRatePercent: drop.weight != null && totalWeight > 0
            ? (drop.weight! / totalWeight) * 100
            : null,
      ),
  ];
}

num? _minNum(num? left, num? right) {
  if (left == null) return right;
  if (right == null) return left;
  return left < right ? left : right;
}

num? _maxNum(num? left, num? right) {
  if (left == null) return right;
  if (right == null) return left;
  return left > right ? left : right;
}
