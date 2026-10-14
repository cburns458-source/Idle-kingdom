import 'dart:convert';

import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

String _smithingKind(String name) {
  final n = name.toLowerCase();
  if (RegExp(r'\bshield\b').hasMatch(n)) return 'shield';
  if (RegExp(r'\b(helmet|chestplate|platelegs|boots|gloves)\b').hasMatch(n)) return 'armor';
  if (RegExp(r'\b(pickaxe|hatchet|fishing rod|harpoon|axe)\b').hasMatch(n) &&
      !n.contains('battleaxe')) {
    return 'tool';
  }
  if (RegExp(r'\b(sword|dagger|warhammer|battleaxe|spear)\b').hasMatch(n)) return 'weapon';
  return 'other';
}

const _town = 'LOC-0025';
const _furnaceActivity = 'ACT-0018';
const _masterDwarf = 'NPC-0003';
const _metallurgy = 'SKL-0008';
const _smithing = 'SKL-0011';
const _might = 'SKL-0001';
const _vitality = 'SKL-0016';

const _tungstenOre = 'ITEM-0010';
const _titaniumOre = 'ITEM-0009';
const _copperOre = 'ITEM-0003';
const _tinOre = 'ITEM-0004';
const _ironOre = 'ITEM-0005';
const _tungstenBar = 'ITEM-0080';
const _titaniumBar = 'ITEM-0079';
const _ironwoodTimber = 'ITEM-0408';
const _mahoganyTimber = 'ITEM-0218';
const _tungstenSword = 'ITEM-0263';
const _titaniumSword = 'ITEM-0250';
const _titaniumHelmet = 'ITEM-0254';

const _tungstenBarRecipe = 'RCP-0020';
const _titaniumBarRecipe = 'RCP-0019';
const _tungstenSwordProject = 'PRJ-0110';
const _titaniumSwordProject = 'PRJ-0097';

PlayerSave _withLevels(PlayerSave save, Map<String, num> levels) {
  return save.copyWith(
    skills: [
      for (final skill in save.skills)
        if (levels.containsKey(skill.skillId))
          skill.copyWith(level: levels[skill.skillId]!)
        else
          skill,
    ],
  );
}

void main() {
  late GameDatabase db;
  late GameDatabase launch;

  setUpAll(() {
    db = assertGameDatabaseShape(contentDatabaseJson());
    launch = filterLaunchContent(db);
  });

  PlayerSave smelter(num metallurgy) {
    var save = _withLevels(createNewSave(launch, 0), {_metallurgy: metallurgy});
    save = save.copyWith(currentLocationId: _town);
    save = addItemToInventory(save, _tungstenOre, 20);
    save = addItemToInventory(save, _titaniumOre, 20);
    save = addItemToInventory(save, _copperOre, 10);
    save = addItemToInventory(save, _tinOre, 10);
    save = addItemToInventory(save, _ironOre, 10);
    return save;
  }

  PlayerSave smith({required num smithing, required num metallurgy}) {
    var save = _withLevels(createNewSave(launch, 0), {
      _smithing: smithing,
      _metallurgy: metallurgy,
    });
    save = save.copyWith(currentLocationId: _town, unlockedNpcIds: const [_masterDwarf]);
    save = addItemToInventory(save, _tungstenBar, 20);
    save = addItemToInventory(save, _titaniumBar, 20);
    save = addItemToInventory(save, _ironwoodTimber, 10);
    save = addItemToInventory(save, _mahoganyTimber, 10);
    return save;
  }

  test('bars unlock at Metallurgy 60 and 70 with the recorded ingredients', () {
    final tungsten = getRecipe(launch, _tungstenBarRecipe)!;
    expect(tungsten.proficiencyLevel, 60);
    expect(tungsten.ingredient1ItemId, _tungstenOre);
    expect(tungsten.ingredient1Quantity, 2);
    expect(tungsten.ingredient2ItemId, _tinOre);
    expect(tungsten.ingredient2Quantity, 1);
    expect(launch.actions.firstWhere((row) => row.actionId == 'ACN-0136').proficiencyLevel, 60);

    final titanium = getRecipe(launch, _titaniumBarRecipe)!;
    expect(titanium.proficiencyLevel, 70);
    expect(titanium.ingredient1ItemId, _titaniumOre);
    expect(titanium.ingredient1Quantity, 2);
    expect(titanium.ingredient2ItemId, _ironOre);
    expect(titanium.ingredient3ItemId, _copperOre);
    expect(launch.actions.firstWhere((row) => row.actionId == 'ACN-0135').proficiencyLevel, 70);
  });

  test('every tungsten and titanium smithing project gates on 60 / 70 for both skills', () {
    for (var i = 105; i <= 117; i += 1) {
      final id = 'PRJ-${i.toString().padLeft(4, '0')}';
      final project = launch.projects.firstWhere((row) => row.projectId == id);
      expect(project.displayName, startsWith('Tungsten '), reason: id);
      expect([project.requiredSkill1Id, project.requiredSkill1Level], [_smithing, 60], reason: id);
      expect(
        [project.requiredSkill2Id, project.requiredSkill2Level],
        [_metallurgy, 60],
        reason: id,
      );
    }
    for (var i = 92; i <= 104; i += 1) {
      final id = 'PRJ-${i.toString().padLeft(4, '0')}';
      final project = launch.projects.firstWhere((row) => row.projectId == id);
      expect(project.displayName, startsWith('Titanium '), reason: id);
      expect([project.requiredSkill1Id, project.requiredSkill1Level], [_smithing, 70], reason: id);
      expect(
        [project.requiredSkill2Id, project.requiredSkill2Level],
        [_metallurgy, 70],
        reason: id,
      );
    }
  });

  test('mining the ores did not move (tungsten 55, titanium 70)', () {
    expect(launch.actions.firstWhere((row) => row.actionId == 'ACN-0027').proficiencyLevel, 55);
    expect(
      launch.requirements.firstWhere((row) => row.requirementId == 'REQ-0042').requiredValue,
      55,
    );
    expect(launch.actions.firstWhere((row) => row.actionId == 'ACN-0026').proficiencyLevel, 70);
  });

  test('refuses tungsten smelting at Metallurgy 59 and allows it at 60', () {
    final refused = beginProductionQueue(
      launch,
      smelter(59),
      _furnaceActivity,
      _tungstenBarRecipe,
      1,
      0,
    );
    expect(refused.ok, isFalse);
    expect(refused.reason, 'You have not learned that recipe yet.');

    final queued = beginProductionQueue(
      launch,
      smelter(60),
      _furnaceActivity,
      _tungstenBarRecipe,
      1,
      0,
    );
    expect(queued.ok, isTrue);
    expect(queued.save!.productionRecipeId, _tungstenBarRecipe);
    expect(inventoryCount(queued.save!, _tungstenOre), 18);
    expect(inventoryCount(queued.save!, _tinOre), 9);
  });

  test('refuses titanium smelting at Metallurgy 69 and allows it at 70', () {
    final refused = beginProductionQueue(
      launch,
      smelter(69),
      _furnaceActivity,
      _titaniumBarRecipe,
      1,
      0,
    );
    expect(refused.ok, isFalse);
    expect(refused.reason, 'You have not learned that recipe yet.');

    final queued = beginProductionQueue(
      launch,
      smelter(70),
      _furnaceActivity,
      _titaniumBarRecipe,
      1,
      0,
    );
    expect(queued.ok, isTrue);
    expect(queued.save!.productionRecipeId, _titaniumBarRecipe);
    expect(inventoryCount(queued.save!, _titaniumOre), 18);
    expect(inventoryCount(queued.save!, _ironOre), 9);
    expect(inventoryCount(queued.save!, _copperOre), 9);
  });

  test('refuses tungsten smithing below 60 on either skill and allows it at 60 / 60', () {
    final lowSmithing = completeSpecialProject(
      launch,
      smith(smithing: 59, metallurgy: 60),
      _tungstenSwordProject,
      1,
      nowMs: 0,
    );
    expect(lowSmithing.ok, isFalse);
    expect(lowSmithing.reason, 'Requires Smithing level 60.');

    final lowMetallurgy = completeSpecialProject(
      launch,
      smith(smithing: 60, metallurgy: 59),
      _tungstenSwordProject,
      1,
      nowMs: 0,
    );
    expect(lowMetallurgy.ok, isFalse);
    expect(lowMetallurgy.reason, 'Requires Metallurgy level 60.');

    final forged = completeSpecialProject(
      launch,
      smith(smithing: 60, metallurgy: 60),
      _tungstenSwordProject,
      1,
      nowMs: 0,
    );
    expect(forged.ok, isTrue);
    expect(forged.outputLabel, 'Tungsten Sword');
    expect(inventoryCount(forged.save!, _tungstenSword), 1);
  });

  test('refuses titanium smithing below 70 on either skill and allows it at 70 / 70', () {
    final lowSmithing = completeSpecialProject(
      launch,
      smith(smithing: 69, metallurgy: 70),
      _titaniumSwordProject,
      1,
      nowMs: 0,
    );
    expect(lowSmithing.ok, isFalse);
    expect(lowSmithing.reason, 'Requires Smithing level 70.');

    final lowMetallurgy = completeSpecialProject(
      launch,
      smith(smithing: 70, metallurgy: 69),
      _titaniumSwordProject,
      1,
      nowMs: 0,
    );
    expect(lowMetallurgy.ok, isFalse);
    expect(lowMetallurgy.reason, 'Requires Metallurgy level 70.');

    final forged = completeSpecialProject(
      launch,
      smith(smithing: 70, metallurgy: 70),
      _titaniumSwordProject,
      1,
      nowMs: 0,
    );
    expect(forged.ok, isTrue);
    expect(forged.outputLabel, 'Titanium Sword');
    expect(inventoryCount(forged.save!, _titaniumSword), 1);
  });

  test('a save that already holds tungsten and titanium bars and gear still loads and equips', () {
    // Forged under the old 50 / 65 gates: the save format itself did not change,
    // so the stored version is current and only the player's levels are low.
    var before = _withLevels(createNewSave(launch, 0), {
      _metallurgy: 50,
      _smithing: 50,
      _might: 60,
      _vitality: 70,
    });
    before = addItemToInventory(before, _tungstenBar, 7);
    before = addItemToInventory(before, _titaniumBar, 3);
    before = addItemToInventory(before, _tungstenSword, 1);
    before = addItemToInventory(before, _titaniumHelmet, 1);
    final stored = jsonDecode(jsonEncode(before.toJson()));

    final loaded = parseSave(stored, 0);
    expect(inventoryCount(loaded, _tungstenBar), 7);
    expect(inventoryCount(loaded, _titaniumBar), 3);
    expect(inventoryCount(loaded, _tungstenSword), 1);
    expect(inventoryCount(loaded, _titaniumHelmet), 1);
    expect(loaded.skills.firstWhere((skill) => skill.skillId == _metallurgy).level, 50);

    final sword = equipItemFromInventory(launch, loaded, _tungstenSword);
    expect(sword.ok, isTrue, reason: sword.reason);
    expect(sword.save!.equipment.slots['SLOT-0001']?.itemId, _tungstenSword);

    final helmet = equipItemFromInventory(launch, sword.save!, _titaniumHelmet);
    expect(helmet.ok, isTrue, reason: helmet.reason);
    expect(helmet.save!.equipment.slots['SLOT-0003']?.itemId, _titaniumHelmet);
    expect(inventoryCount(helmet.save!, _tungstenBar), 7);
    expect(inventoryCount(helmet.save!, _titaniumBar), 3);
  });

  test('smithing tools and weapons drop leather straps; armor and shields keep them', () {
    final smithing = db.projects.where((row) => row.raw['Skill ID'] == 'SKL-0011');
    expect(smithing.any((row) => _smithingKind(row.displayName) == 'other'), isFalse);

    for (final project in smithing) {
      final kind = _smithingKind(project.displayName);
      final usesStraps = projectInputs(project).any((input) => input.itemId == 'ITEM-0084');
      if (kind == 'tool' || kind == 'weapon') {
        expect(usesStraps, isFalse, reason: project.displayName);
      } else {
        expect(usesStraps, isTrue, reason: project.displayName);
      }
    }
  });

  test('armor and shield smithing XP is 10% higher', () {
    expect(db.projects.firstWhere((row) => row.projectId == 'PRJ-0007').raw['XP Reward'], 2560);
    expect(db.projects.firstWhere((row) => row.projectId == 'PRJ-0003').raw['XP Reward'], 4125);
    expect(db.projects.firstWhere((row) => row.projectId == 'PRJ-0020').raw['XP Reward'], 2723);
    expect(db.projects.firstWhere((row) => row.projectId == 'PRJ-0013').raw['XP Reward'], 7260);
    expect(db.projects.firstWhere((row) => row.projectId == 'PRJ-0025').raw['XP Reward'], 8620);
    expect(db.projects.firstWhere((row) => row.projectId == 'PRJ-0113').raw['XP Reward'], 35822);
  });
}
