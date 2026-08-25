import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase db;
  late PlayerSave save;

  setUpAll(() {
    db = filterLaunchContent(assertGameDatabaseShape(contentDatabaseJson()));
    save = createNewSave(db, 1);
  });

  test('the farm shows combat and harvesting, not every skill', () {
    final skills = skillIdsForLocation(db, save, 'LOC-0001');
    expect(skills, containsAll(<String>[combatSkillId, harvestingSkillId]));
    expect(skills, isNot(contains(fishingSkillId)));
  });

  test('a combat camp includes combat from the fight, not from PvP', () {
    expect(skillIdsForLocation(db, save, 'LOC-0003'), contains(combatSkillId));
  });
}
