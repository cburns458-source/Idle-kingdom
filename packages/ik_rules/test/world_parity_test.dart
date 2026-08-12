import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

const List<String> _travelMaps = <String>['MAP-0001', 'MAP-0002', 'MAP-0006', 'MAP-0007'];
const List<String> _unlockedForView = <String>['LOC-0026'];

List<String> _stringList(ParityFixture fixture, String key) {
  return fixture.inputField<List<Object?>>(key).map((value) => value! as String).toList();
}

LocationRow? _location(GameDatabase db, String locationId) {
  return db.locations.firstWhereOrNull((row) => row.raw['Location ID'] == locationId);
}

Map<String, Object?> _claimJson(LocationSearchClaimResult result) {
  return <String, Object?>{
    'ok': result.ok,
    'save': result.save.toJson(),
    'reason': result.reason,
    'itemId': result.itemId,
    'itemName': result.itemName,
    'quantity': result.quantity,
  };
}

void main() {
  group('travel connection parity', () {
    for (final fixture in loadParityFixtures('world/travel/connections')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final locations = _stringList(fixture, 'locations');
        expect(
          checkParity(fixture, {
            'byLocation': locations
                .map(
                  (locationId) => <String, Object?>{
                    'locationId': locationId,
                    'from': connectionsFrom(
                      db,
                      locationId,
                    ).map((row) => row.raw['Connection ID']).toList(),
                    'durations': connectionsFrom(
                      db,
                      locationId,
                    ).map((row) => travelDurationMs(row)).toList(),
                  },
                )
                .toList(),
            'pairs': locations
                .expand(
                  (from) => locations.map(
                    (to) => <String, Object?>{
                      'from': from,
                      'to': to,
                      'connectionId': findConnection(db, from, to)?.raw['Connection ID'],
                    },
                  ),
                )
                .toList(),
            'missingDuration': <num>[travelDurationMs(null), travelDurationMs(null)],
          }),
          isNull,
        );
      });
    }
  });

  group('map view parity', () {
    for (final fixture in loadParityFixtures('world/travel/maps')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        expect(
          checkParity(fixture, {
            'byMap': _stringList(fixture, 'mapIds')
                .map(
                  (mapId) => <String, Object?>{
                    'mapId': mapId,
                    'locked': locationsForMapView(
                      db,
                      mapId,
                    ).map((row) => row.raw['Location ID']).toList(),
                    'unlocked': locationsForMapView(
                      db,
                      mapId,
                      _unlockedForView,
                    ).map((row) => row.raw['Location ID']).toList(),
                  },
                )
                .toList(),
            'activeMap': _stringList(fixture, 'locations').map((locationId) {
              final location = _location(db, locationId);
              return <String, Object?>{
                'locationId': locationId,
                'mapId': location == null ? null : getLocationMapId(location),
                'activeMapId': location == null ? null : resolveActiveMapId(db, location),
              };
            }).toList(),
          }),
          isNull,
        );
      });
    }
  });

  group('travel reachability parity', () {
    for (final fixture in loadParityFixtures('world/travel/reachability')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final locations = _stringList(fixture, 'locations');
        final results = <Map<String, Object?>>[];
        for (final from in locations) {
          for (final to in locations) {
            for (final mapId in _travelMaps) {
              results.add(<String, Object?>{
                'from': from,
                'to': to,
                'mapId': mapId,
                'locked': canTravelTo(db, from, to, mapId),
                'unlocked': canTravelTo(db, from, to, mapId, _unlockedForView),
              });
            }
          }
        }
        expect(checkParity(fixture, {'results': results}), isNull);
      });
    }
  });

  group('travel arrival parity', () {
    for (final fixture in loadParityFixtures('world/travel/arrival')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        final nowMs = fixture.inputField<num>('nowMs');
        expect(
          checkParity(fixture, {
            'arrived': applyTravelArrival(db, save, 'LOC-0001', nowMs).toJson(),
            'sameLocation': applyTravelArrival(db, save, save.currentLocationId, nowMs).toJson(),
          }),
          isNull,
        );
      });
    }
  });

  group('hostile warning parity', () {
    for (final fixture in loadParityFixtures('world/hostility/warnings')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        expect(
          checkParity(fixture, {
            'byLocation': _stringList(fixture, 'locations')
                .map(
                  (locationId) => <String, Object?>{
                    'locationId': locationId,
                    'hostile': hostileActivitiesAt(
                      db,
                      locationId,
                    ).map((row) => row.raw['Activity ID']).toList(),
                  },
                )
                .toList(),
          }),
          isNull,
        );
      });
    }
  });

  group('forced hostility parity', () {
    for (final fixture in loadParityFixtures('world/hostility/forced')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        expect(
          checkParity(fixture, {
            'byLocation': _stringList(fixture, 'locations')
                .map(
                  (locationId) => <String, Object?>{
                    'locationId': locationId,
                    'forced': forcedHostileActivity(db, save, locationId)?.raw['Activity ID'],
                  },
                )
                .toList(),
          }),
          isNull,
        );
      });
    }
  });

  group('hostile arrival parity', () {
    for (final fixture in loadParityFixtures('world/hostility/arrival')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final result = applyHostileTravelArrival(
          db,
          saveOf(fixture),
          fixture.inputField<String>('destination'),
          fixture.inputField<num>('nowMs'),
          Mulberry32(fixture.inputField<num>('seed').toInt()).asFunction,
        );
        expect(
          checkParity(fixture, {
            'save': result.save.toJson(),
            'forcedActivityId': result.forcedActivityId,
            'forceBlockedReason': result.forceBlockedReason,
            'threatenedActivityId': result.threatenedActivityId,
            'message': hostileForceMessage(db, result),
          }),
          isNull,
        );
      });
    }
  });

  group('hostile message parity', () {
    for (final fixture in loadParityFixtures('world/hostility/message')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        HostileTravelArrivalResult result({
          String? forcedActivityId,
          String? forceBlockedReason,
          String? threatenedActivityId,
        }) {
          return HostileTravelArrivalResult(
            save: save,
            forcedActivityId: forcedActivityId,
            forceBlockedReason: forceBlockedReason,
            threatenedActivityId: threatenedActivityId,
          );
        }

        expect(
          checkParity(fixture, {
            'noThreat': hostileForceMessage(db, result()),
            'unknownForced': hostileForceMessage(
              db,
              result(forcedActivityId: 'ACT-9999', threatenedActivityId: 'ACT-9999'),
            ),
            'unknownBlocked': hostileForceMessage(
              db,
              result(forceBlockedReason: 'Requirements not met.', threatenedActivityId: 'ACT-9999'),
            ),
            'neither': hostileForceMessage(db, result(threatenedActivityId: 'ACT-0002')),
          }),
          isNull,
        );
      });
    }
  });

  group('location search cooldown parity', () {
    for (final fixture in loadParityFixtures('world/search/spots')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        final nowMs = fixture.inputField<num>('nowMs');
        final claimed = save.copyWith(
          locationSearchClaims: <String, String>{
            'SRCH-0001': isoFromMs(nowMs - 60000),
            'SRCH-0002': 'not-a-date',
          },
        );
        expect(
          checkParity(fixture, {
            'byLocation': _stringList(fixture, 'locations').map((locationId) {
              final searches = locationSearchesAt(db, locationId).map((search) {
                final searchId = search.raw['Search ID']! as String;
                return <String, Object?>{
                  'searchId': searchId,
                  'freshRemaining': locationSearchCooldownRemainingMs(save, search, nowMs),
                  'freshReady': canClaimLocationSearch(save, search, nowMs),
                  'claimedRemaining': locationSearchCooldownRemainingMs(claimed, search, nowMs),
                  'claimedReady': canClaimLocationSearch(claimed, search, nowMs),
                  'afterCooldown': canClaimLocationSearch(
                    claimed,
                    search,
                    nowMs + 25 * 60 * 60 * 1000,
                  ),
                  'unparseableClaim': locationSearchCooldownRemainingMs(
                    claimed.copyWith(
                      locationSearchClaims: <String, String>{searchId: 'not-a-date'},
                    ),
                    search,
                    nowMs,
                  ),
                };
              }).toList();
              return <String, Object?>{'locationId': locationId, 'searches': searches};
            }).toList(),
          }),
          isNull,
        );
      });
    }
  });

  group('location search claim parity', () {
    for (final fixture in loadParityFixtures('world/search/claim')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final searchId = fixture.inputField<String>('searchId');
        final nowMs = fixture.inputField<num>('nowMs');
        final first = claimLocationSearch(db, saveOf(fixture), searchId, nowMs);
        final again = claimLocationSearch(db, first.save, searchId, nowMs + 60000);
        final later = claimLocationSearch(db, first.save, searchId, nowMs + 25 * 60 * 60 * 1000);
        expect(
          checkParity(fixture, {
            'first': _claimJson(first),
            'again': _claimJson(again),
            'later': _claimJson(later),
          }),
          isNull,
        );
      });
    }
  });

  group('map layout parity', () {
    for (final fixture in loadParityFixtures('world/layout')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        expect(
          checkParity(fixture, {
            'byMap': _stringList(fixture, 'mapIds').map((mapId) {
              final nodes =
                  layoutForMap(mapId).entries
                      .map(
                        (entry) => <String, Object?>{
                          'locationId': entry.key,
                          'x': entry.value.x,
                          'y': entry.value.y,
                        },
                      )
                      .toList()
                    ..sort(
                      (a, b) =>
                          jsLocaleCompare(a['locationId']! as String, b['locationId']! as String),
                    );
              return <String, Object?>{'mapId': mapId, 'nodes': nodes};
            }).toList(),
            'byLocation': db.locations
                .map(
                  (location) => <String, Object?>{
                    'locationId': location.raw['Location ID'],
                    'position': positionForLocation(location).toJson(),
                  },
                )
                .toList(),
          }),
          isNull,
        );
      });
    }
  });
}
