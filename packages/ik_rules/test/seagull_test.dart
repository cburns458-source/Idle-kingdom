import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

GameDatabase _db() => filterLaunchContent(assertGameDatabaseShape(contentDatabaseJson()));

/// Every entry of [poolId], by the action it points at.
Map<String, num> _weights(GameDatabase db, String poolId) {
  final weights = <String, num>{};
  for (final entry in db.poolEntries) {
    if (entry.raw['Pool ID'] != poolId) continue;
    weights[entry.raw['Action ID']! as String] = entry.raw['Weight']! as num;
  }
  return weights;
}

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = _db();
  });

  test('the Seagull is a dock nuisance with no loot', () {
    final enemy = getEnemy(db, 'ENM-0021')!;
    expect(enemy.raw['Display Name'], 'Seagull');
    expect(enemy.raw['Location ID'], 'LOC-0004');
    expect(enemy.raw['Maximum HP'], 100);
    expect(enemy.raw['Min Damage'], 20);
    expect(enemy.raw['Max Damage'], 40);
    expect(enemy.raw['Drop Chance'], 0);
    expect(enemy.raw['Reward Table ID'], isNull);

    final action = db.actions.firstWhere((row) => row.raw['Action ID'] == 'ACN-0173');
    expect(action.raw['Display Name'], 'Fight seagull');
    expect(action.raw['Category'], 'Combat');
    expect(action.raw['Target ID'], 'ENM-0021');
  });

  test('a seagull turns up one roll in five while reasoning with the pirates', () {
    final weights = _weights(db, 'POOL-0018');
    expect(weights['ACN-0173'], 20);
    expect(weights['ACN-0091'], 80);
    expect(weights.values.reduce((a, b) => a + b), 100);
  });

  test('dock fishing is only tuna and shark', () {
    final weights = _weights(db, 'POOL-0004');
    expect(weights, {'ACN-0102': 55, 'ACN-0103': 45});
    expect(weights.containsKey('ACN-0173'), isFalse);
    expect(weights.values.reduce((a, b) => a + b), 100);
  });

  test('reasoning with the pirates can still hand out the seagull fight', () {
    final activity = db.activities.firstWhere((row) => row.activityId == 'ACT-0022');
    final poolId = activity.raw['Pool ID']! as String;
    expect(_weights(db, poolId).containsKey('ACN-0173'), isTrue);
  });

  test('rolling the seagull at the pirates starts a real fight against it', () {
    final save = createNewSave(db, 0).copyWith(currentLocationId: 'LOC-0004');

    // The seagull is the last entry of the pool, so the highest roll picks it.
    final started = requestActivityStart(db, save, 'ACT-0022', 0, () => 0.99);
    expect(started.ok, isTrue);
    expect(started.save!.currentActionId, 'ACN-0173');
    expect(started.save!.combatEnemyId, 'ENM-0021');
    expect(started.save!.combatEnemyHp, 100);
  });

  test('dock fishing rolls tuna or shark, never a seagull', () {
    var save = raiseSkillToMinimumLevel(createNewSave(db, 0), db, 'SKL-0001', 60).save;
    save = raiseSkillToMinimumLevel(save, db, 'SKL-0003', 65).save;
    final fisher = equipStackToSlot(
      save.copyWith(currentLocationId: 'LOC-0004'),
      weaponToolSlotId,
      'ITEM-0103',
      1,
    );

    final tuna = requestActivityStart(db, fisher, 'ACT-0004', 0, () => 0);
    expect(tuna.ok, isTrue);
    expect(tuna.save!.currentActionId, 'ACN-0102');
    expect(tuna.save!.combatEnemyId, isNull);

    final shark = requestActivityStart(db, fisher, 'ACT-0004', 0, () => 0.99);
    expect(shark.ok, isTrue);
    expect(shark.save!.currentActionId, 'ACN-0103');
    expect(shark.save!.combatEnemyId, isNull);
  });
}
