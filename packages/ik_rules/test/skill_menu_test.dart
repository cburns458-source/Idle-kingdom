import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = assertGameDatabaseShape(contentDatabaseJson());
  });

  test('menus use number then name', () {
    final mining = skillMenuDisplayEntries(db, 'SKL-0002');
    expect(mining, isNotEmpty);
    expect(skillMenuLine(mining.first), matches(RegExp(r'^\d+\. .+')));
    expect(mining.any((row) => skillMenuLine(row).contains('Mine copper ore')), isTrue);
  });

  test('smithing groups the same material at one level on Basic metal', () {
    final view = skillMenuView(db, smithingSkillId);
    expect(view.tabs.map((tab) => tab.label), ['Basic metal']);
    final rows = skillMenuDisplayEntries(db, smithingSkillId);
    expect(rows.any((row) => row.displayName == 'Tungsten items' && row.level == 70), isTrue);
    expect(rows.where((row) => row.displayName == 'Tungsten Sword'), isEmpty);
    expect(projectsForSkill(db, smithingSkillId).length, greaterThan(rows.length));
    expect(
      view.tabs.first.sections.first.entries.any(
        (row) => row.displayName == 'Steel items' && row.level == 35,
      ),
      isTrue,
    );
    expect(
      view.tabs.first.sections
          .expand((section) => section.entries)
          .any((row) => row.displayName == 'Steel Battleaxe'),
      isFalse,
    );
    expect(
      view.tabs.first.sections
          .expand((section) => section.entries)
          .any((row) => row.displayName == 'Warhammer'),
      isFalse,
    );
    expect(
      view.tabs.first.sections
          .expand((section) => section.entries)
          .any((row) => row.displayName == 'Steel Warhammer'),
      isFalse,
    );
  });

  test('quest-only actions stay off the skill menu', () {
    expect(actionIsQuestOnly(db, 'ACN-0171'), isTrue);
    expect(
      actionsForSkill(db, combatSkillId).any((row) => row.displayName == 'Pressure the guards'),
      isFalse,
    );
    expect(
      skillMenuDisplayEntries(db, combatSkillId).any((row) => row.displayName.contains('Pressure')),
      isFalse,
    );
    expect(actionsForSkill(db, combatSkillId).any((row) => row.displayName == 'Monk'), isTrue);
  });

  test('combat enemies use combat level and the enemy name', () {
    final view = skillMenuView(db, combatSkillId);
    expect(view.tabs.first.label, 'Enemies');
    final goblin = view.tabs.first.sections.first.entries.firstWhere(
      (row) => row.displayName == 'Goblin Scout',
    );
    expect(goblin.level, isNotNull);
    expect(skillMenuLine(goblin), matches(RegExp(r'^\d+\. Goblin Scout$')));
    expect(view.tabs.map((tab) => tab.label), ['Enemies', 'Equipment', 'Weapons', 'Other']);
    final weapons = view.tabs
        .firstWhere((tab) => tab.id == 'weapons')
        .sections
        .expand((section) => section.entries);
    expect(weapons.any((row) => row.displayName == 'Wooden weapons'), isFalse);
    expect(weapons.any((row) => row.displayName == 'Tungsten weapons'), isTrue);
    expect(weapons.any((row) => row.displayName == 'Steel weapons'), isTrue);
    expect(weapons.any((row) => row.displayName == 'Wooden Sword'), isFalse);
    expect(weapons.any((row) => row.displayName == 'Tungsten Sword'), isFalse);
    expect(weapons.any((row) => row.displayName == 'Steel Warhammer'), isFalse);
    expect(weapons.any((row) => row.displayName == 'Cedar Bow'), isFalse);
    expect(weapons.any((row) => row.displayName == 'Tungsten Shield'), isFalse);
    final gear = view.tabs
        .firstWhere((tab) => tab.id == 'gear')
        .sections
        .expand((section) => section.entries);
    expect(gear.any((row) => row.displayName == 'Tungsten equipment'), isTrue);
    expect(gear.any((row) => row.displayName == 'Reinforced Steel equipment'), isTrue);
    expect(gear.any((row) => row.displayName == 'Bull Horn equipment'), isFalse);
    expect(gear.any((row) => row.displayName == 'Wooden equipment'), isFalse);
    expect(gear.any((row) => row.displayName == 'Leather equipment' && row.level == 1), isTrue);
    expect(gear.any((row) => row.displayName == 'Leather Helmet'), isFalse);
    expect(gear.any((row) => row.displayName == 'Tungsten Helmet'), isFalse);
    expect(gear.any((row) => row.displayName == 'Tungsten Shield'), isFalse);
    expect(gear.any((row) => row.displayName == 'Tungsten Sword'), isFalse);
    final other = view.tabs
        .firstWhere((tab) => tab.id == 'other')
        .sections
        .expand((section) => section.entries);
    expect(other.any((row) => row.displayName == 'Bull Horn Helmet'), isTrue);
    expect(other.any((row) => row.displayName == 'Wooden Sword' && row.level == 1), isTrue);
    expect(other.any((row) => row.displayName == 'Leather Helmet'), isFalse);
    expect(other.any((row) => row.displayName == 'Leather equipment'), isFalse);
    expect(other.any((row) => row.displayName == 'Cedar Bow'), isTrue);
    expect(other.any((row) => row.displayName == 'Boar Spear'), isTrue);
  });

  test('hunting tools include net and sling', () {
    final hunting = skillMenuView(db, huntingSkillId);
    expect(hunting.tabs.map((tab) => tab.label), ['Actions', 'Tools']);
    final tools = hunting.tabs.firstWhere((tab) => tab.id == 'tools').sections.first.entries;
    expect(tools.any((row) => row.displayName == 'Net' && row.level == 1), isTrue);
    expect(tools.any((row) => row.displayName == 'Sling' && row.level == 5), isTrue);
    expect(tools.any((row) => row.displayName == 'Noose Wand' && row.level == 25), isTrue);
    expect(tools.any((row) => row.displayName == 'Magic Net' && row.level == 45), isTrue);
  });

  test('arcana lists Essence at level 1 on its own tab', () {
    final arcana = skillMenuView(db, arcanaSkillId);
    expect(arcana.tabs.map((tab) => tab.label), ['Essence', 'Spells', 'Weapons', 'Enchantments']);
    final essence = arcana.tabs.firstWhere((tab) => tab.id == 'essence').sections.first.entries;
    expect(essence.any((row) => row.displayName == 'Essence' && row.level == 1), isTrue);
    expect(
      actionsForSkill(db, miningSkillId).any((row) => row.displayName.contains('essence')),
      isFalse,
    );
  });

  test('gathering tools include the wooden starters at level 1', () {
    final mining = skillMenuView(db, miningSkillId);
    expect(mining.tabs.map((tab) => tab.label), ['Actions', 'Tools']);
    expect(
      mining.tabs.last.sections.first.entries.any(
        (row) => row.displayName == 'Wooden Pickaxe' && row.level == 1,
      ),
      isTrue,
    );
  });

  test('artisanry puts Lucky Necklace on Jewelry', () {
    final view = skillMenuView(db, artisanrySkillId);
    expect(view.tabs.map((tab) => tab.label), contains('Jewelry'));
    final jewelry = view.tabs.firstWhere((tab) => tab.id == 'jewelry').sections.first.entries;
    expect(jewelry.any((row) => row.displayName == 'Lucky Necklace' && row.level == 25), isTrue);
    final other = view.tabs.firstWhere((tab) => tab.id == 'other').sections.first.entries;
    expect(other.any((row) => row.displayName == 'Leather equipment' && row.level == 1), isTrue);
    expect(other.any((row) => row.displayName == 'Leather Helmet'), isFalse);
    expect(other.any((row) => row.displayName == 'Leather Gloves'), isFalse);
    final helmet = db.equipment.firstWhere((row) => row.raw['Item ID'] == 'ITEM-0308');
    expect(helmet.raw['HP Bonus'], 15);
    expect(helmet.raw['Damage Reduction'], 0);
  });

  test('cooking lists cooked squid and soup, and the book keeps locked recipes', () {
    final cooking = actionsForSkill(db, 'SKL-0007');
    expect(
      cooking.any((row) => row.displayName == 'Cooked Baby Giant Squid' && row.level == 80),
      isTrue,
    );
    expect(cooking.any((row) => row.displayName == 'Squid noodle soup' && row.level == 80), isTrue);

    final save = createNewSave(db, 0);
    final book = recipeBookForSkill(save, db, 'SKL-0007');
    expect(book, isNotEmpty);
    expect(book.any((entry) => entry.known), isTrue);
    expect(book.any((entry) => entry.name.contains('Baby Giant Squid') && !entry.known), isTrue);
    expect(
      listRecipeBookEntries(
        save,
        db,
      ).any((entry) => entry.name == 'Cooked Baby Giant Squid' && !entry.known),
      isTrue,
    );
    expect(
      listRecipeBookEntries(save, db).any((entry) => entry.name == 'Squid Noodle Soup'),
      isTrue,
    );
    expect(
      listRecipeBookEntries(save, db).any((entry) => entry.name == 'Leather Helmet' && entry.known),
      isTrue,
    );
  });

  test('launch recipe book names Ancient Binding and Starroot', () {
    final launch = filterLaunchContent(db);
    final save = createNewSave(launch, 0);
    final entries = listRecipeBookEntries(save, launch);
    final gloves = entries.firstWhere((entry) => entry.name == "Falconer's Gloves");
    expect(gloves.materials, contains('Ancient Binding'));
    expect(gloves.materials, isNot(contains('ITEM-0290')));
    final squid = entries.firstWhere((entry) => entry.name == 'Cooked Baby Giant Squid');
    expect(squid.materials, contains('Starroot'));
    expect(squid.materials, isNot(contains('ITEM-0208')));
  });

  test('recipe books expand skill-menu groups into individual rows', () {
    final save = createNewSave(db, 0);
    final smithing = recipeBookView(save, db, smithingSkillId);
    expect(smithing.tabs.map((tab) => tab.label), contains('Basic metal'));
    final steel = smithing.tabs.first.sections.where((section) => section.title == 'Steel items');
    expect(steel, isNotEmpty);
    expect(steel.first.entries.any((entry) => entry.name == 'Steel Sword'), isTrue);
    expect(steel.first.entries.any((entry) => entry.name == 'Steel items'), isFalse);

    final artisanry = recipeBookView(save, db, artisanrySkillId);
    expect(
      artisanry.tabs.map((tab) => tab.label),
      containsAll(<String>['Bows', 'Jewelry', 'Other']),
    );
    final other = artisanry.tabs.firstWhere((tab) => tab.id == 'other');
    expect(other.sections.any((section) => section.title == 'Leather equipment'), isTrue);
    expect(
      other.sections
          .expand((section) => section.entries)
          .any((entry) => entry.name == 'Leather Helmet'),
      isTrue,
    );
  });

  test('squid noodle soup heals 1,100', () {
    final item = db.items.firstWhere((row) => row.itemId == 'ITEM-0302');
    expect(item.displayName, 'Squid Noodle Soup');
    final equipment = db.equipment.firstWhere((row) => row.raw['Item ID'] == 'ITEM-0302');
    expect(equipment.raw['Healing Amount'], 1100);
    final action = db.actions.firstWhere((row) => row.actionId == 'ACN-0127');
    expect(action.proficiencyLevel, 80);
    expect(action.releasePhase, 'Launch');
    final recipe = db.recipes.firstWhere((row) => row.raw['Recipe ID'] == 'RCP-0044');
    expect(recipe.raw['Proficiency Level'], 80);
    expect(recipe.raw['Release Phase'], 'Launch');
  });
}
