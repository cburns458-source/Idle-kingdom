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

  test('smithing groups the same material at one level', () {
    final rows = skillMenuDisplayEntries(db, smithingSkillId);
    expect(rows.any((row) => row.displayName == 'Tungsten items' && row.level == 70), isTrue);
    expect(rows.where((row) => row.displayName == 'Tungsten Sword'), isEmpty);
    expect(projectsForSkill(db, smithingSkillId).length, greaterThan(rows.length));
  });
}
