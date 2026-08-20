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

  test('citadel gathering cuts poplar, not cedar', () {
    final activity = db.activities.firstWhere((row) => row.activityId == 'ACT-0032');
    expect(activity.raw['Contextual Name'], 'Cut poplar trees');
    expect(activity.raw['Location ID'], 'LOC-0031');
    expect(_weights(db, activity.raw['Pool ID']! as String), {'ACN-0048': 100});
  });

  test('the abandoned mineshaft can fish the same dock pool', () {
    final activity = db.activities.firstWhere((row) => row.activityId == 'ACT-0038');
    expect(activity.raw['Contextual Name'], 'Fish the deep pools');
    expect(activity.raw['Location ID'], 'LOC-0022');
    expect(activity.raw['Pool ID'], 'POOL-0004');
    expect(_weights(db, 'POOL-0004'), {'ACN-0102': 55, 'ACN-0103': 45});
  });
}
