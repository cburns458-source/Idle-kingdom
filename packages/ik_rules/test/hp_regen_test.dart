import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = assertGameDatabaseShape(contentDatabaseJson());
  });

  test('waits 60s then heals 1% max HP per minute, doubling each streak step', () {
    expect(naturalHpRegenIdleSeconds, 60);
    expect(naturalHpRegenBasePercent, 1);
    expect(naturalHpRegenTriggerMs, 60000);
    expect(naturalHpRegenIdleMs(), 60000);
    final base = createNewSave(db, 0);
    final maxHp = playerMaxHp(db, base);
    const now = 1000 * 60 * 60.0;
    final save = base.copyWith(currentHp: 1);
    final firstHeal = naturalHpRegenHealAmount(maxHp, 0);
    final minute = applyNaturalHpRegen(db, save, 60000, now);
    expect(minute.save.currentHp, 1 + firstHeal);
    expect(minute.save.hpRegenStreak, 1);
    expect(minute.remainderMs, 0);

    final twoMinutes = applyNaturalHpRegen(db, save, 120000, now);
    final secondHeal = naturalHpRegenHealAmount(maxHp, 1);
    expect(twoMinutes.save.currentHp, 1 + firstHeal + secondHeal);
    expect(twoMinutes.save.hpRegenStreak, 2);
  });

  test('still regens in combat once the idle gate has passed', () {
    final base = createNewSave(db, 0);
    final maxHp = playerMaxHp(db, base);
    const now = 1000 * 60 * 60.0;
    final save = base.copyWith(
      currentHp: 1,
      combatEnemyId: 'ENM-0001',
      lastDamagedAt: isoFromMs(now - 120000),
    );
    final result = applyNaturalHpRegen(db, save, 60000, now);
    expect(result.save.currentHp, 1 + naturalHpRegenHealAmount(maxHp, 0));
  });

  test('blocks regen for 60s after damage and resets the streak', () {
    final base = createNewSave(db, 0);
    const now = 1000 * 60 * 60.0;
    final damaged = notePlayerDamaged(base.copyWith(currentHp: 1, hpRegenStreak: 3), now - 30000);
    expect(damaged.hpRegenStreak, 0);
    final blocked = applyNaturalHpRegen(db, damaged, 30000, now);
    expect(blocked.save.currentHp, 1);
    expect(blocked.remainderMs, 0);

    final afterGate = applyNaturalHpRegen(db, damaged, 90000, now + 60000);
    final maxHp = playerMaxHp(db, base);
    expect(afterGate.save.currentHp, 1 + naturalHpRegenHealAmount(maxHp, 0));
  });

  test('still regens during thievery and other non-combat work', () {
    final base = createNewSave(db, 0);
    final maxHp = playerMaxHp(db, base);
    const now = 1000 * 60 * 60.0;
    final save = base.copyWith(currentHp: 1, currentActivityId: 'ACT-0012');
    expect(applyNaturalHpRegen(db, save, 60000, now).save.currentHp, 1 + naturalHpRegenHealAmount(maxHp, 0));
  });

  test('caps at max HP, clears streak, and keeps a remainder only while damaged', () {
    final base = createNewSave(db, 0);
    final maxHp = playerMaxHp(db, base);
    const now = 1000 * 60 * 60.0;
    final almost = applyNaturalHpRegen(db, base.copyWith(currentHp: maxHp - 1), 60000, now);
    expect(almost.save.currentHp, maxHp);
    expect(almost.save.hpRegenStreak, 0);
    expect(almost.remainderMs, 0);
    final partial = applyNaturalHpRegen(db, base.copyWith(currentHp: 1), 2500, now);
    expect(partial.save.currentHp, 1);
    expect(partial.remainderMs, 2500);
  });

  test('leaves blessing surplus above max alone', () {
    final base = createNewSave(db, 0);
    final maxHp = playerMaxHp(db, base);
    final surplus = maxHp + (maxHp * 0.1).floor();
    const now = 1000 * 60 * 60.0;
    final result = applyNaturalHpRegen(db, base.copyWith(currentHp: surplus), 60000, now);
    expect(result.save.currentHp, surplus);
    expect(result.remainderMs, 0);
  });
}
