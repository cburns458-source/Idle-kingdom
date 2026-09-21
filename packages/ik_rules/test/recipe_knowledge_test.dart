import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

PlayerSave _withLevels(PlayerSave save, Map<String, num> levels) {
  return save.copyWith(
    skills: save.skills
        .map(
          (skill) => levels.containsKey(skill.skillId)
              ? skill.copyWith(level: levels[skill.skillId]!)
              : skill,
        )
        .toList(),
  );
}

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = assertGameDatabaseShape(contentDatabaseJson());
  });

  test('lockpicks need Crafting 20 and Thievery 20 to make', () {
    final recipe = getRecipe(db, 'RCP-0062');
    expect(recipe, isNotNull);
    expect(isAutomaticLevelUnlock(recipe!), isTrue);

    final base = createNewSave(db, 0);
    final crafter = _withLevels(base, const <String, num>{'SKL-0009': 20});
    expect(knowsRecipe(crafter, db, 'RCP-0062'), isTrue);
    expect(canKnowRecipe(crafter, db, recipe), isFalse);

    final both = _withLevels(base, const <String, num>{'SKL-0009': 20, 'SKL-0015': 20});
    expect(canKnowRecipe(both, db, recipe), isTrue);

    final withBar = addItemToInventory(crafter, 'ITEM-0076', 1);
    final refused = beginProductionQueue(db, withBar, 'ACT-0019', 'RCP-0062', 1, 0);
    expect(refused.ok, isFalse);
    expect(refused.reason, contains('Thievery'));

    final queued = beginProductionQueue(
      db,
      addItemToInventory(both, 'ITEM-0076', 1),
      'ACT-0019',
      'RCP-0062',
      1,
      0,
    );
    expect(queued.ok, isTrue);
  });
}
