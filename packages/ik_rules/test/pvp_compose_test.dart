import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

GameDatabase _db() => filterLaunchContent(assertGameDatabaseShape(contentDatabaseJson()));

PlayerSave _withCombat(PlayerSave save, num level) {
  return save.copyWith(
    skills: [
      for (final skill in save.skills)
        skill.skillId == combatSkillId ? skill.copyWith(level: level) : skill,
    ],
  );
}

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = _db();
  });

  test('compose uses snapshot gear and live combat and race', () {
    final base = createNewSave(db, 0);
    final sword = equipStackToSlot(
      base,
      weaponToolSlotId,
      'ITEM-0128',
      1,
    ).copyWith(raceId: 'RACE-0001');
    final gathering = equipStackToSlot(
      _withCombat(base, 20).copyWith(raceId: 'RACE-0003'),
      weaponToolSlotId,
      'ITEM-0102',
      1,
    );

    final fighter = composePvpFighter(db, gathering, sword);
    expect(slotItemId(fighter, weaponToolSlotId), 'ITEM-0128');
    expect(combatLevelOf(fighter), 20);
    expect(fighter.raceId, 'RACE-0003');
    expect(slotItemId(gathering, weaponToolSlotId), 'ITEM-0102');

    final stale = composePvpFighter(db, sword, sword);
    expect(playerMaxHp(db, fighter), greaterThan(playerMaxHp(db, stale)));
    expect(playerDamageRange(db, fighter).min, greaterThan(playerDamageRange(db, gathering).min));
  });

  test('overlay keeps snapshot gear and copies live combat and race', () {
    final base = createNewSave(db, 0);
    final snapshot = equipStackToSlot(base, weaponToolSlotId, 'ITEM-0128', 1);
    final live = equipStackToSlot(
      _withCombat(base, 20).copyWith(raceId: 'RACE-0004'),
      weaponToolSlotId,
      'ITEM-0102',
      1,
    );

    final merged = overlayPvpLiveStats(snapshot, live);
    expect(slotItemId(merged, weaponToolSlotId), 'ITEM-0128');
    expect(combatLevelOf(merged), 20);
    expect(merged.raceId, 'RACE-0004');
  });
}
