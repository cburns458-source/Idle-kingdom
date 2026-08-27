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

  test('kingswoods rare wood is cedar and oak', () {
    final activity = db.activities.firstWhere((row) => row.activityId == 'ACT-0026');
    expect(activity.raw['Contextual Name'], 'Search for rare wood');
    expect(activity.raw['Location ID'], 'LOC-0008');
    expect(_weights(db, activity.raw['Pool ID']! as String), {'ACN-0046': 70, 'ACN-0047': 30});
  });

  test('catch crawfish and hunt pheasant sit on the early gather curve', () {
    final crawfish = db.actions.firstWhere((row) => row.raw['Action ID'] == 'ACN-0099');
    expect(crawfish.raw['XP Reward'], 200);
    expect(crawfish.raw['Base Duration Seconds'], 10);
    final pheasant = db.actions.firstWhere((row) => row.raw['Action ID'] == 'ACN-0017');
    expect(pheasant.raw['XP Reward'], 3000);
    expect(pheasant.raw['Base Duration Seconds'], 120);
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

  test('the abandoned mineshaft fishes tuna, shark, and baby giant squid', () {
    final activity = db.activities.firstWhere((row) => row.activityId == 'ACT-0038');
    expect(activity.raw['Contextual Name'], 'Fish the deep pools');
    expect(activity.raw['Location ID'], 'LOC-0022');
    expect(activity.raw['Pool ID'], 'POOL-0028');
    expect(_weights(db, 'POOL-0028'), {'ACN-0102': 50, 'ACN-0103': 45, 'ACN-0104': 5});
    expect(_weights(db, 'POOL-0004'), {'ACN-0102': 55, 'ACN-0103': 45});
  });
}
