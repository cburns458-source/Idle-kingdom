import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

GameDatabase _db() => filterLaunchContent(assertGameDatabaseShape(contentDatabaseJson()));

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = _db();
  });

  test('existing enemies keep table HP/damage as bases and scale from Might/Vitality', () {
    final save = createNewSave(db, 0);
    final cow = getEnemy(db, 'ENM-0001')!;
    final scout = getEnemy(db, 'ENM-0003')!;

    expect(enemyMightLevel(cow), 1);
    expect(enemyVitalityLevel(cow), 1);
    expect(enemyCombatLevel(cow), 2);
    expect(enemyScaledMaxHp(cow), 100);
    expect(enemyEncounterMaxHp(db, save, cow), 100);
    expect(enemyEncounterDamageRange(db, save, cow).toJson(), {'min': 10, 'max': 20});

    expect(enemyMightLevel(scout), 10);
    expect(enemyVitalityLevel(scout), 10);
    expect(enemyCombatLevel(scout), 15);
    expect(enemyScaledMaxHp(scout), 462);
    expect(enemyScaledDamageRange(scout).toJson(), {'min': 33, 'max': 66});
    expect(enemyEncounterMaxHp(db, save, scout), 462);
    expect(enemyEncounterDamageRange(db, save, scout).toJson(), {'min': 33, 'max': 66});
  });

  test('new enemies have no location, drops, or pool entries', () {
    const added = <(String, String, num, num, num, num, num)>[
      ('ENM-0025', 'Giant Rat', 3, 150, 12, 26, 200),
      ('ENM-0026', 'Bandit', 6, 260, 16, 40, 350),
      ('ENM-0027', 'Cave Bat', 14, 580, 37, 73, 870),
      ('ENM-0028', 'Mage Apprentice', 18, 750, 45, 90, 1200),
      ('ENM-0029', 'Bandit Captain', 22, 930, 55, 108, 1600),
      ('ENM-0030', 'Harpy', 48, 3860, 152, 268, 9000),
      ('ENM-0031', 'Giant', 51, 4440, 164, 288, 10800),
      ('ENM-0032', 'Gargoyle', 58, 5940, 192, 338, 16600),
      ('ENM-0033', 'Wyvern', 67, 7920, 236, 404, 26000),
      ('ENM-0034', 'Cyclops', 70, 9000, 260, 440, 31250),
      ('ENM-0035', 'Demon', 82, 15000, 475, 745, 64500),
      ('ENM-0036', 'Greater Gargoyle', 86, 17760, 555, 860, 82000),
    ];
    final addedIds = {for (final row in added) row.$1};
    for (final row in added) {
      final enemy = getEnemy(db, row.$1)!;
      expect(enemy.displayName, row.$2);
      expect(enemyMightLevel(enemy), row.$3);
      expect(enemyVitalityLevel(enemy), row.$3);
      expect(enemyCombatLevel(enemy), combatLevelFromSkills(row.$3, row.$3));
      expect(enemy.maximumHp, row.$4);
      expect(enemy.minDamage, row.$5);
      expect(enemy.maxDamage, row.$6);
      expect(enemy.combatXp, row.$7);
      expect(enemy.locationId, isNull);
      expect(enemy.dropChance, 0);
      expect(enemy.rewardTableId, isNull);
      expect(enemy.minimumGold, 0);
      expect(enemy.maximumGold, 0);
    }
    expect(db.actions.any((action) => addedIds.contains(action.raw['Target ID'])), isFalse);
    expect(
      db.poolEntries.any((entry) {
        for (final action in db.actions) {
          if (action.actionId != entry.raw['Action ID']) continue;
          return addedIds.contains(action.raw['Target ID']);
        }
        return false;
      }),
      isFalse,
    );
  });
}
