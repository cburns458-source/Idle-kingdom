import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = assertGameDatabaseShape(contentDatabaseJson());
  });

  PlayerSave atLevel(String skillId, num level, {List<String> mentors = const []}) {
    var save = createNewSave(db, 0);
    if (level > 1) save = raiseSkillToMinimumLevel(save, db, skillId, level).save;
    if (mentors.isNotEmpty) save = save.copyWith(unlockedNpcIds: mentors);
    return save;
  }

  test('crafting 9 to 10 unlocks Leather Straps', () {
    final save = atLevel('SKL-0009', 10);
    final unlocks = skillUnlocksBetween(db, save, 'SKL-0009', 9, 10);
    expect(unlocks.recipes, contains('Leather Straps'));
  });

  test('combat level-ups never list fight or enemy action names', () {
    final save = atLevel(combatSkillId, 20);
    final unlocks = skillUnlocksBetween(db, save, combatSkillId, 1, 20);
    final names = [
      ...unlocks.unlockedActivities,
      ...unlocks.proficientActivities,
      ...unlocks.recipes,
      ...unlocks.projects,
    ];
    expect(names.any((name) => name.startsWith('Fight ')), isFalse);
    expect(names, isNot(contains('Cow')));
    expect(names, isNot(contains('Goblin Scout')));
    for (final action in db.actions.where((row) => row.category == 'Combat')) {
      expect(names, isNot(contains(action.displayName)));
    }
  });

  test('artisanry 24 to 25 lists Noose Wand without a mentor', () {
    final save = atLevel(artisanrySkillId, 25);
    final unlocks = skillUnlocksBetween(db, save, artisanrySkillId, 24, 25);
    expect(unlocks.projects, contains('Noose Wand'));
    expect(unlocks.projects, contains('Lucky Necklace'));
    expect(unlocks.projects, isNot(contains('Cedar Bow')));
  });

  test('arcana 39 to 40 lists Magic Net only after the Archmage', () {
    final locked = skillUnlocksBetween(db, atLevel(arcanaSkillId, 40), arcanaSkillId, 39, 40);
    expect(locked.projects, isNot(contains('Magic Net')));

    final taught = atLevel(arcanaSkillId, 40, mentors: [archmageId]);
    final unlocks = skillUnlocksBetween(db, taught, arcanaSkillId, 39, 40);
    expect(unlocks.projects, contains('Magic Net'));
  });

  test('mining 4 to 5 names the copper-mine activity, not the ore action', () {
    final save = atLevel('SKL-0002', 5);
    final unlocks = skillUnlocksBetween(db, save, 'SKL-0002', 4, 5);
    expect(unlocks.proficientActivities, contains('Work the copper mine'));
    expect(unlocks.proficientActivities, isNot(contains('Mine tin ore')));
  });
}
