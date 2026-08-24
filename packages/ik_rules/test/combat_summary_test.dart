import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  late GameDatabase db;
  late PlayerSave save;

  setUpAll(() {
    final fixture = loadParityFixtures('combat/stats').firstWhere((row) => row.name == 'geared');
    db = databaseOf(fixture);
    save = saveOf(fixture);
  });

  test('totals match the live combat helpers', () {
    final summary = playerCombatStatSummary(db, save);
    final damage = playerDamageRange(db, save);
    final offhand = playerOffhandDamageRange(db, save);

    expect(summary.damage.min, damage.min);
    expect(summary.damage.max, damage.max);
    expect(summary.offhandDamage?.min, offhand?.min);
    expect(summary.offhandDamage?.max, offhand?.max);
    expect(summary.maxHp, playerMaxHp(db, save));
    expect(summary.damageReduction, playerDamageReduction(db, save));
  });

  test('lists enchantment, spell, potion, and race bonuses', () {
    final summary = playerCombatStatSummary(db, save);
    expect(
      summary.activeBonuses.map((bonus) => bonus.kind),
      containsAll(<String>['enchantment', 'spell', 'potion', 'race']),
    );
    expect(
      summary.activeBonuses.map((bonus) => bonus.name),
      containsAll(<String>[
        'Minor Combat Enchantment',
        'Thorns',
        'Strength Spell ×2',
        'Abundance Spell',
        'Strength Potion',
        'High Elf',
      ]),
    );
    expect(
      summary.activeBonuses.firstWhere((bonus) => bonus.kind == 'race').effect,
      contains('maximum HP'),
    );
  });

  test('breakdown names the inputs that feed each total', () {
    final summary = playerCombatStatSummary(db, save);

    expect(summary.mainhandBreakdown.map((line) => line.label), isNot(contains('Unarmed')));
    expect(summary.mainhandBreakdown.map((line) => line.label), contains('Steel Sword'));
    expect(summary.mainhandBreakdown.map((line) => line.label), contains('Enchantments'));
    expect(summary.mainhandBreakdown.map((line) => line.label), contains('Combat Level 25'));
    expect(summary.mainhandBreakdown.map((line) => line.label), contains('Strength Spell'));
    expect(summary.mainhandBreakdown.map((line) => line.label), contains('Strength Potion'));
    expect(summary.mainhandBreakdown.lastWhere((line) => line.label == 'Total').detail, '165–297');

    final offhand = playerOffhandDamageRange(db, save);
    if (offhand != null) {
      expect(summary.offhandBreakdown.map((line) => line.label), contains('Combat Level 25'));
      expect(summary.offhandBreakdown.last.label, 'Total');
    } else {
      expect(summary.offhandBreakdown, isEmpty);
    }

    expect(summary.healthBreakdown.map((line) => line.label), isNot(contains('Base')));
    expect(summary.healthBreakdown.map((line) => line.label), contains('Steel Helmet'));
    expect(summary.healthBreakdown.map((line) => line.label), contains('High Elf'));
    expect(summary.healthBreakdown.last.detail, '1647');

    expect(summary.reductionBreakdown.map((line) => line.label), contains('Steel Helmet'));
    expect(summary.reductionBreakdown.last.detail, '1');
  });

  test('lists action time reduction from equipped tools', () {
    final db = filterLaunchContent(assertGameDatabaseShape(contentDatabaseJson()));
    final save = equipStackToSlot(createNewSave(db, 0), weaponToolSlotId, 'ITEM-0110', 1);
    final summary = playerCombatStatSummary(db, save);
    expect(summary.activeBonuses.map((bonus) => bonus.kind), contains('equipment'));
    expect(summary.activeBonuses.map((bonus) => bonus.name), contains('Action time reduction'));
    expect(
      summary.activeBonuses.firstWhere((bonus) => bonus.name == 'Action time reduction').effect,
      contains('5%'),
    );
  });

  test('an unarmed save still lists Unarmed as a main-hand source', () {
    final fixture = loadParityFixtures('combat/stats').firstWhere((row) => row.name == 'base');
    final summary = playerCombatStatSummary(databaseOf(fixture), saveOf(fixture));

    expect(summary.mainhandBreakdown.map((line) => line.label), contains('Unarmed'));
    expect(summary.mainhandBreakdown.last.label, 'Total');
    expect(summary.offhandBreakdown, isEmpty);
  });
}
