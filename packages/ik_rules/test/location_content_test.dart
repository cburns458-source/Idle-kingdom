import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

GameDatabase _db() => filterLaunchContent(assertGameDatabaseShape(contentDatabaseJson()));

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

  test('the river node is labelled The Docks', () {
    expect(db.locations.firstWhere((row) => row.locationId == 'LOC-0004').displayName, 'The Docks');
  });

  test('citadel gathering cuts poplar and oak', () {
    final activity = db.activities.firstWhere((row) => row.activityId == 'ACT-0032');
    expect(activity.raw['Contextual Name'], 'Cut poplar and oak trees');
    expect(activity.raw['Location ID'], 'LOC-0031');
    expect(_weights(db, activity.raw['Pool ID']! as String), {'ACN-0048': 60, 'ACN-0047': 40});
  });

  test('citadel gathering also hunts pheasant and gathers wild roots', () {
    final hunt = db.activities.firstWhere((row) => row.activityId == 'ACT-0051');
    expect(hunt.raw['Contextual Name'], 'Hunt pheasant');
    expect(hunt.raw['Location ID'], 'LOC-0031');
    expect(_weights(db, hunt.raw['Pool ID']! as String), {'ACN-0017': 100});

    final roots = db.activities.firstWhere((row) => row.activityId == 'ACT-0052');
    expect(roots.raw['Contextual Name'], 'Gather wild roots');
    expect(roots.raw['Location ID'], 'LOC-0031');
    expect(_weights(db, roots.raw['Pool ID']! as String), {'ACN-0105': 100});

    final pheasant = db.actions.firstWhere((row) => row.raw['Action ID'] == 'ACN-0017');
    expect(pheasant.raw['Reward Table ID'], 'RWT-0052');
    expect(pheasant.raw['Secondary Reward Table ID'], 'RWT-0119');
    expect(pheasant.raw['Tertiary Reward Table ID'], isNull);
  });

  test('kingswoods rare wood is cedar and oak', () {
    final activity = db.activities.firstWhere((row) => row.activityId == 'ACT-0026');
    expect(activity.raw['Contextual Name'], 'Search for rare wood');
    expect(activity.raw['Location ID'], 'LOC-0008');
    expect(_weights(db, activity.raw['Pool ID']! as String), {'ACN-0046': 70, 'ACN-0047': 30});
  });

  test('Hunt rabbit sits at hunting 5', () {
    final rabbit = db.actions.firstWhere((row) => row.raw['Action ID'] == 'ACN-0016');
    expect(rabbit.raw['Display Name'], 'Hunt rabbit');
    expect(rabbit.raw['Proficiency Level'], 5);
  });

  test('catch perch and hunt pheasant sit on the early gather curve', () {
    final crawfish = db.actions.firstWhere((row) => row.raw['Action ID'] == 'ACN-0099');
    expect(crawfish.raw['XP Reward'], 240);
    expect(crawfish.raw['Base Duration Seconds'], 12);
    final pheasant = db.actions.firstWhere((row) => row.raw['Action ID'] == 'ACN-0017');
    expect(pheasant.raw['XP Reward'], 825);
    expect(pheasant.raw['Base Duration Seconds'], 12);
  });

  test('enemy gold is a tenth, with animals that never paid staying at zero', () {
    num gold(String id, String key) {
      final enemy = db.enemies.firstWhere((row) => row.raw['Enemy ID'] == id);
      return enemy.raw[key]! as num;
    }

    expect(gold('ENM-0001', 'Minimum Gold'), 0);
    expect(gold('ENM-0002', 'Maximum Gold'), 0);
    expect(gold('ENM-0010', 'Minimum Gold'), 0);
    expect(gold('ENM-0010', 'Maximum Gold'), 0);
    expect(gold('ENM-0003', 'Minimum Gold'), 1);
    expect(gold('ENM-0003', 'Maximum Gold'), 3);
    expect(gold('ENM-0016', 'Minimum Gold'), 3);
    expect(gold('ENM-0006', 'Maximum Gold'), 1000);
  });

  test('a location danger line is only for places with a hostile activity', () {
    expect(locationShowsDangerWarning(db, 'LOC-0003'), isTrue);
    expect(locationShowsDangerWarning(db, 'LOC-0004'), isTrue);
    expect(locationShowsDangerWarning(db, 'LOC-0021'), isTrue);
    expect(locationShowsDangerWarning(db, 'LOC-0037'), isTrue);
    expect(locationShowsDangerWarning(db, 'LOC-0018'), isFalse);
    expect(locationShowsDangerWarning(db, 'LOC-0007'), isFalse);
    expect(locationShowsDangerWarning(db, 'LOC-0002'), isFalse);
  });

  test('the abandoned mineshaft fishes shark, man of war, and baby giant squid', () {
    final activity = db.activities.firstWhere((row) => row.activityId == 'ACT-0038');
    expect(activity.raw['Contextual Name'], 'Fish the deep pools');
    expect(activity.raw['Location ID'], 'LOC-0022');
    expect(activity.raw['Pool ID'], 'POOL-0028');
    expect(_weights(db, 'POOL-0028'), {'ACN-0103': 50, 'ACN-0215': 30, 'ACN-0104': 20});
    expect(_weights(db, 'POOL-0004'), {
      'ACN-0215': 50,
      'ACN-0173': 5,
      'ACN-0103': 35,
      'ACN-0216': 10,
    });
  });

  test('kingswoods hunting keeps gather boar; woodland supplies rolls combat boar', () {
    expect(_weights(db, 'POOL-0009').keys.toSet(), {'ACN-0014', 'ACN-0017', 'ACN-0204'});
    expect(_weights(db, 'POOL-0010').keys, contains('ACN-0008'));
    expect(_weights(db, 'POOL-0010')['ACN-0008'], 10);
    expect(activityHasMixedCombatPool(db, 'ACT-0010'), isTrue);
    expect(activityHasMixedCombatPool(db, 'ACT-0009'), isFalse);
    expect(activityHasMixedCombatPool(db, 'ACT-0006'), isTrue);
    expect(activityHasMixedCombatPool(db, 'ACT-0004'), isTrue);
    expect(activityHasMixedCombatPool(db, 'ACT-0016'), isFalse);
    expect(activityHasMixedCombatPool(db, 'ACT-0001'), isFalse);
    expect(activityHasMixedCombatPool(db, 'ACT-0012'), isFalse);
  });
}
