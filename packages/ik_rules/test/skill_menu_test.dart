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
    expect(view.tabs.map((tab) => tab.label), ['Basic metal', 'Other']);
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
      view.tabs.last.sections
          .expand((section) => section.entries)
          .any((row) => row.displayName == 'Warhammer'),
      isTrue,
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
    expect(
      view.tabs.last.sections
          .expand((section) => section.entries)
          .any((row) => row.displayName == 'Wooden Sword' && row.level == 1),
      isTrue,
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
  });

  test('cooking lists cooked squid and soup, and the book is known recipes only', () {
    final cooking = actionsForSkill(db, 'SKL-0007');
    expect(
      cooking.any((row) => row.displayName == 'Cooked Baby Giant Squid' && row.level == 75),
      isTrue,
    );
    expect(cooking.any((row) => row.displayName == 'Squid noodle soup' && row.level == 80), isTrue);

    final save = createNewSave(db, 0);
    final book = recipeBookForSkill(save, db, 'SKL-0007');
    expect(book, isNotEmpty);
    expect(book.every((entry) => entry.known), isTrue);
    expect(book.any((entry) => entry.name.contains('Baby Giant Squid')), isFalse);
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
  });

  test('squid noodle soup heals 1,100', () {
    final item = db.items.firstWhere((row) => row.itemId == 'ITEM-0302');
    expect(item.displayName, 'Squid Noodle Soup');
    final equipment = db.equipment.firstWhere((row) => row.raw['Item ID'] == 'ITEM-0302');
    expect(equipment.raw['Healing Amount'], 1100);
    final action = db.actions.firstWhere((row) => row.actionId == 'ACN-0127');
    expect(action.proficiencyLevel, 75);
    expect(action.releasePhase, 'Launch');
    final recipe = db.recipes.firstWhere((row) => row.raw['Recipe ID'] == 'RCP-0044');
    expect(recipe.raw['Proficiency Level'], 75);
    expect(recipe.raw['Release Phase'], 'Launch');
  });
}
