import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  group('timer spot prune parity', () {
    for (final fixture in loadParityFixtures('timers/prune-locked-spots')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final lockedFarm = saveOf(fixture, 'lockedFarm');
        final lockedGrowing = saveOf(fixture, 'lockedGrowing');
        final unlockedFarm = saveOf(fixture, 'unlockedFarm');
        expect(
          checkParity(fixture, {
            'dropsLockedFarm': pruneLockedTimerSpots(db, lockedFarm).toJson(),
            'keepsGrowing': pruneLockedTimerSpots(db, lockedGrowing).toJson(),
            'keepsUnlocked': pruneLockedTimerSpots(db, unlockedFarm).toJson(),
            'farmDiscoverLocked': discoverUnlockedFarmSpot(db, lockedFarm).toJson(),
            'farmDiscoverUnlocked': discoverUnlockedFarmSpot(db, unlockedFarm).toJson(),
          }),
          isNull,
        );
      });
    }
  });
}
