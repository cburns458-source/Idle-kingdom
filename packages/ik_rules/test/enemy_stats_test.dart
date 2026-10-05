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

  test('player Might/Vitality bonuses start at skill level 5', () {
    final save = createNewSave(db, 0);
    expect(mightDamageMultiplier(save), 1);
    expect(vitalityHpMultiplier(save), 1);
    expect(playerMaxHp(db, save), 1000);
    final level5 = save.copyWith(
      skills: save.skills
          .map(
            (skill) => skill.skillId == mightSkillId || skill.skillId == vitalitySkillId
                ? skill.copyWith(level: 5)
                : skill,
          )
          .toList(),
    );
    expect(mightDamageMultiplier(level5), closeTo(1.05, 0.0001));
    expect(vitalityHpMultiplier(level5), closeTo(1.05, 0.0001));
    expect(playerMaxHp(db, level5), 1050);
  });

  test('existing enemies keep table HP/damage as bases and scale from Might/Vitality', () {
    final save = createNewSave(db, 0);
    final cow = getEnemy(db, 'ENM-0001')!;
    final scout = getEnemy(db, 'ENM-0003')!;

    expect(enemyMightLevel(cow), 1);
    expect(enemyVitalityLevel(cow), 5);
    expect(enemyCombatLevel(cow), 5);
    expect(enemyScaledMaxHp(cow), 105);
    expect(enemyCombatXp(cow), 52);
    expect(enemyEncounterMaxHp(db, save, cow), 105);
    expect(enemyEncounterDamageRange(db, save, cow).toJson(), {'min': 10, 'max': 20});

    expect(enemyMightLevel(scout), 12);
    expect(enemyVitalityLevel(scout), 10);
    expect(enemyCombatLevel(scout), 17);
    expect(enemyScaledMaxHp(scout), 462);
    expect(enemyCombatXp(scout), 231);
    expect(enemyScaledDamageRange(scout).toJson(), {'min': 33, 'max': 67});
    expect(enemyEncounterMaxHp(db, save, scout), 462);
    expect(enemyEncounterDamageRange(db, save, scout).toJson(), {'min': 33, 'max': 67});
  });

  test('new enemies keep placeholder stats; mountain roosts have locations', () {
    final source = assertGameDatabaseShape(contentDatabaseJson());
    // id, name, might, vitality, baseHp, minDmg, maxDmg, combatXp, locationId
    const launchEnemies = <(String, String, num, num, num, num, num, num, String?)>[
      ('ENM-0025', 'Giant Rat', 5, 5, 150, 12, 26, 78, 'LOC-0011'),
      ('ENM-0026', 'Bandit', 15, 6, 260, 16, 40, 137, 'LOC-0052'),
      ('ENM-0027', 'Cave Bat', 14, 8, 580, 37, 73, 313, 'LOC-0046'),
      ('ENM-0029', 'Bandit Captain', 26, 16, 930, 55, 108, 539, 'LOC-0052'),
      ('ENM-0030', 'Harpy', 70, 40, 3860, 152, 268, 2702, 'LOC-0047'),
      ('ENM-0031', 'Giant', 60, 50, 4440, 164, 288, 3330, 'LOC-0049'),
      ('ENM-0033', 'Wyvern', 85, 60, 7920, 236, 404, 6336, 'LOC-0047'),
      ('ENM-0034', 'Cyclops', 75, 70, 9000, 260, 440, 7650, 'LOC-0049'),
    ];
    const expansionEnemies = <(String, String, num, num, num, num, num, num, String?)>[
      ('ENM-0028', 'Mage Apprentice', 25, 12, 750, 45, 90, 420, null),
      ('ENM-0032', 'Gargoyle', 65, 60, 5940, 192, 338, 4752, null),
      ('ENM-0035', 'Demon', 90, 65, 15000, 475, 745, 12375, null),
      ('ENM-0036', 'Greater Gargoyle', 90, 75, 17760, 555, 860, 15540, null),
    ];
    final placeholderIds = {
      for (final row in launchEnemies) row.$1,
      for (final row in expansionEnemies) row.$1,
    };
    final assignedIds = {for (final row in launchEnemies) row.$1};
    for (final row in launchEnemies) {
      final enemy = getEnemy(db, row.$1)!;
      expect(enemy.displayName, row.$2);
      expect(enemyMightLevel(enemy), row.$3);
      expect(enemyVitalityLevel(enemy), row.$4);
      expect(enemyCombatLevel(enemy), combatLevelFromSkills(row.$3, row.$4));
      expect(enemy.maximumHp, row.$5);
      expect(enemy.minDamage, row.$6);
      expect(enemy.maxDamage, row.$7);
      expect(enemy.combatXp, row.$8);
      expect(enemyCombatXp(enemy), row.$8);
      expect(enemy.locationId, row.$9);
      if (row.$1 == 'ENM-0027') {
        expect(enemy.dropChance, 25);
        expect(enemy.rewardTableId, 'RWT-0186');
      } else if (row.$1 == 'ENM-0030') {
        expect(enemy.dropChance, 25);
        expect(enemy.rewardTableId, 'RWT-0188');
      } else if (row.$1 == 'ENM-0031') {
        expect(enemy.dropChance, 20);
        expect(enemy.rewardTableId, 'RWT-0190');
      } else if (row.$1 == 'ENM-0033') {
        expect(enemy.dropChance, 25);
        expect(enemy.rewardTableId, 'RWT-0189');
      } else if (row.$1 == 'ENM-0034') {
        expect(enemy.dropChance, 10);
        expect(enemy.rewardTableId, 'RWT-0187');
      } else {
        expect(enemy.dropChance, 0);
        expect(enemy.rewardTableId, isNull);
      }
      if (row.$1 == 'ENM-0026') {
        expect(enemy.minimumGold, 1);
        expect(enemy.maximumGold, 2);
      } else if (row.$1 == 'ENM-0029') {
        expect(enemy.minimumGold, 5);
        expect(enemy.maximumGold, 6);
      } else {
        expect(enemy.minimumGold, 0);
        expect(enemy.maximumGold, 0);
      }
    }
    for (final row in expansionEnemies) {
      expect(getEnemy(db, row.$1), isNull);
      final enemy = getEnemy(source, row.$1)!;
      expect(enemy.raw['Release Phase'], 'Expansion');
      expect(enemy.displayName, row.$2);
      expect(enemyMightLevel(enemy), row.$3);
      expect(enemyVitalityLevel(enemy), row.$4);
      expect(enemyCombatLevel(enemy), combatLevelFromSkills(row.$3, row.$4));
      expect(enemy.maximumHp, row.$5);
      expect(enemy.minDamage, row.$6);
      expect(enemy.maxDamage, row.$7);
      expect(enemy.combatXp, row.$8);
      expect(enemyCombatXp(enemy), row.$8);
      expect(enemy.locationId, row.$9);
    }
    expect(
      source.actions.any((action) {
        final target = action.raw['Target ID'];
        return target is String && placeholderIds.contains(target) && !assignedIds.contains(target);
      }),
      isFalse,
    );
    expect(
      source.poolEntries.any((entry) {
        for (final action in source.actions) {
          if (action.actionId != entry.raw['Action ID']) continue;
          final target = action.raw['Target ID'];
          return target is String &&
              placeholderIds.contains(target) &&
              !assignedIds.contains(target);
        }
        return false;
      }),
      isFalse,
    );
  });
}
