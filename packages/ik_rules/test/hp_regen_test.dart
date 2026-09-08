import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = assertGameDatabaseShape(contentDatabaseJson());
  });

  test('grants 1 HP every 6 seconds and 10 per minute', () {
    expect(naturalHpRegenPerMinute, 10);
    expect(naturalHpRegenIntervalMs(), 6000);
    final save = createNewSave(db, 0).copyWith(currentHp: 1);
    expect(applyNaturalHpRegen(db, save, 6000).save.currentHp, 2);
    expect(applyNaturalHpRegen(db, save, 6000).remainderMs, 0);
    expect(applyNaturalHpRegen(db, save, 60000).save.currentHp, 11);
  });

  test('skips regen in combat and drops leftover', () {
    final save = createNewSave(db, 0).copyWith(currentHp: 1, combatEnemyId: 'ENM-0001');
    final result = applyNaturalHpRegen(db, save, 60000);
    expect(result.save.currentHp, 1);
    expect(result.remainderMs, 0);
  });

  test('still regens during thievery and other non-combat work', () {
    final save = createNewSave(db, 0).copyWith(currentHp: 1, currentActivityId: 'ACT-0012');
    expect(applyNaturalHpRegen(db, save, 6000).save.currentHp, 2);
  });

  test('caps at max HP and keeps a remainder only while damaged', () {
    final base = createNewSave(db, 0);
    final maxHp = playerMaxHp(db, base);
    final almost = applyNaturalHpRegen(db, base.copyWith(currentHp: maxHp - 1), 12000);
    expect(almost.save.currentHp, maxHp);
    expect(almost.remainderMs, 0);
    final partial = applyNaturalHpRegen(db, base.copyWith(currentHp: 1), 2500);
    expect(partial.save.currentHp, 1);
    expect(partial.remainderMs, 2500);
  });
}
