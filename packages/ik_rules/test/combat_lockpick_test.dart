import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = assertGameDatabaseShape(contentDatabaseJson());
  });

  test('lockpicks in Weapon/Tool deal 0 enemy damage every round', () {
    final base = createNewSave(db, 0);
    final save = base.copyWith(
      equipment: base.equipment.copyWith(
        slots: <String, EquippedStack?>{
          ...base.equipment.slots,
          weaponToolSlotId: const EquippedStack(itemId: lockpickItemId, quantity: 5),
        },
      ),
    );
    final action = db.actions.firstWhere((row) => row.actionId == 'ACN-0001');
    final enemy = db.enemies.firstWhere((row) => row.enemyId == 'ENM-0001');
    final started = beginCombatSave(db, save, action, enemy, '2026-01-01T00:00:00.000Z');
    final maxHp = enemyEncounterMaxHp(db, started, enemy);
    final round = resolveCombatRound(db, started, enemy, maxHp, () => 0.999);

    expect(round.playerHit, 0);
    expect(round.playerCrit, isFalse);
    expect(round.offhandHit, isNull);
    expect(round.staffHit, isNull);
    expect(round.thornsHit, 0);
    expect(round.enemyHp, maxHp);
    expect(round.enemyHit, greaterThan(0));
    expect(round.outcome, 'ongoing');
  });

  test('off-hand dagger still hits when lockpicks deal no main-hand damage', () {
    final base = createNewSave(db, 0);
    final save = base.copyWith(
      equipment: base.equipment.copyWith(
        slots: <String, EquippedStack?>{
          ...base.equipment.slots,
          weaponToolSlotId: const EquippedStack(itemId: lockpickItemId, quantity: 5),
          offhandSlotId: const EquippedStack(itemId: 'ITEM-0125', quantity: 1),
        },
      ),
    );
    final action = db.actions.firstWhere((row) => row.actionId == 'ACN-0001');
    final enemy = db.enemies.firstWhere((row) => row.enemyId == 'ENM-0001');
    final started = beginCombatSave(db, save, action, enemy, '2026-01-01T00:00:00.000Z');
    final maxHp = enemyEncounterMaxHp(db, started, enemy);
    final round = resolveCombatRound(db, started, enemy, maxHp, () => 0);

    expect(round.playerHit, 0);
    expect(round.offhandHit, greaterThan(0));
    expect(round.enemyHp, maxHp - (round.offhandHit ?? 0));
    expect(round.staffHit, isNull);
  });
}
