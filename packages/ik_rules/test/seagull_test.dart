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

  test('a seagull turns up one roll in twenty while fishing the coast', () {
    final weights = _weights(db, 'POOL-0004');
    expect(weights['ACN-0173'], 5);
    expect(weights.values.reduce((a, b) => a + b), 100);

    // The catches keep their order: trout is still the common one.
    expect(weights['ACN-0100'], greaterThan(weights['ACN-0101']!));
    expect(weights['ACN-0101'], greaterThan(weights['ACN-0102']!));
  });

  test('both dock activities can hand out the seagull fight', () {
    for (final activityId in <String>['ACT-0022', 'ACT-0004']) {
      final activity = db.activities.firstWhere((row) => row.activityId == activityId);
      final poolId = activity.raw['Pool ID']! as String;
      expect(
        _weights(db, poolId).containsKey('ACN-0173'),
        isTrue,
        reason: '$activityId should be able to roll a seagull',
      );
    }
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

  test('rolling the seagull while fishing interrupts the catch with a fight', () {
    // The dock is hostile until the pirates stop being a threat, and fishing
    // wants a rod in hand, so this is what a fisher at the coast looks like.
    final base = raiseSkillToMinimumLevel(createNewSave(db, 0), db, 'SKL-0001', 60).save;
    final fisher = equipStackToSlot(
      base.copyWith(currentLocationId: 'LOC-0004'),
      weaponToolSlotId,
      'ITEM-0103',
      1,
    );

    final started = requestActivityStart(db, fisher, 'ACT-0004', 0, () => 0.99);
    expect(started.ok, isTrue);
    expect(started.save!.currentActionId, 'ACN-0173');
    expect(started.save!.combatEnemyId, 'ENM-0021');

    // A lower roll still lands on a fish, so the seagull is the exception.
    final fishing = requestActivityStart(db, fisher, 'ACT-0004', 0, () => 0);
    expect(fishing.ok, isTrue);
    expect(fishing.save!.currentActionId, 'ACN-0100');
    expect(fishing.save!.combatEnemyId, isNull);
  });
}
