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

  ActivePotionEffect? _poison() {
    final equipment = db.equipment.firstWhere((row) => row.raw['Item ID'] == 'ITEM-0073');
    return parsePotionEffect(equipment, 'ITEM-0073');
  }

  test('parses the live poison tag', () {
    expect(_poison()?.enemyMaxHpDamagePercent, 10);
    expect(_poison()?.scope, 'one_combat_encounter');
  });

  test('still parses the old maximum-HP poison tag', () {
    final effect = parsePotionEffect(
      const EquipmentRow({
        'Capabilities / Effects':
            'potion_slot; one_combat_encounter; deals 10% of enemy maximum HP',
      }),
      'ITEM-0073',
    );
    expect(effect?.enemyMaxHpDamagePercent, 10);
  });

  test('beginCombatSave consumes poison without chipping enemy HP', () {
    var save = equipStackToSlot(createNewSave(db, 0), potionSlotId, 'ITEM-0073', 1);
    final enemy = db.enemies.firstWhere((row) => row.raw['Enemy ID'] == 'ENM-0001');
    final action = db.actions.firstWhere((row) => row.raw['Action ID'] == 'ACN-0001');
    final started = beginCombatSave(db, save, action, enemy, '2026-01-01T00:00:00.000Z');

    expect(slotStack(started, potionSlotId), isNull);
    expect(started.combatEnemyHp, enemy.raw['Maximum HP']);
    expect(started.activePotionEffect?.enemyMaxHpDamagePercent, 10);
  });

  test('ticks 10% of current HP and stops at 10% of max', () {
    final effect = _poison();
    expect(potionEnemyHpFloor(1000), 100);
    expect(applyPotionEnemyRoundDamage(1000, 1000, effect), 900);
    expect(applyPotionEnemyRoundDamage(900, 1000, effect), 810);
    expect(applyPotionEnemyRoundDamage(111, 1000, effect), 100);
    expect(applyPotionEnemyRoundDamage(100, 1000, effect), 100);
    expect(applyPotionEnemyRoundDamage(5, 1000, effect), 5);
    expect(applyPotionEnemyRoundDamage(1000, 1000, null), 1000);
  });
}
