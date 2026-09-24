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

  test('Mountains is a world-map gateway onto The Slopes', () {
    final gate = db.locations.firstWhere((row) => row.locationId == mountainsGatewayId);
    expect(gate.raw['Display Name'], 'Mountains');
    expect(gate.raw['Map ID'], mainMapId);
    expect(isSubMapGateway(gate), isTrue);
    expect(landingLocationIdFor(gate), theSlopesId);
    expect(gate.raw['Hidden On Map IDs'], mountainsMapId);

    final slopes = db.locations.firstWhere((row) => row.locationId == theSlopesId);
    expect(slopes.raw['Display Name'], 'The Slopes');
    expect(slopes.raw['Map ID'], mountainsMapId);
    expect(slopes.raw['Parent Location ID'], mountainsGatewayId);

    expect(
      locationsForMapView(db, mainMapId).any((row) => row.locationId == mountainsGatewayId),
      isTrue,
    );
    expect(
      locationsForMapView(db, mountainsMapId).any((row) => row.locationId == mountainsGatewayId),
      isFalse,
    );
    expect(
      locationsForMapView(db, mountainsMapId).map((row) => row.locationId),
      containsAll(<String>[theSlopesId, 'LOC-0036', thePeakId, badlandsId, giantCampId]),
    );
  });

  test('the old mountain work sits on The Slopes', () {
    expect(
      db.activities
          .where((row) => row.raw['Location ID'] == theSlopesId)
          .map((row) => row.activityId),
      containsAll(<String>['ACT-0006', 'ACT-0027', 'ACT-0065']),
    );
    expect(db.npcs.firstWhere((row) => row.npcId == 'NPC-0003').locationId, theSlopesId);
    expect(
      db.enemies.firstWhere((row) => row.enemyId == 'ENM-0007').raw['Location ID'],
      theSlopesId,
    );
    expect(locationHasBotanyPatch(theSlopesId), isTrue);
    expect(locationHasBotanyPatch(mountainsGatewayId), isFalse);
    expect(locationHasBotanyPatch('LOC-0036'), isTrue);
  });

  test('The Peak, Badlands, and Giant Camp use the written pools', () {
    expect(_weights(db, 'POOL-0050'), {'ACN-0219': 70, 'ACN-0220': 30});
    expect(_weights(db, 'POOL-0051'), {'ACN-0021': 50, 'ACN-0020': 50});
    expect(_weights(db, 'POOL-0052'), {'ACN-0221': 60, 'ACN-0222': 40});

    final peak = db.activities.firstWhere((row) => row.activityId == 'ACT-0068');
    expect(peak.raw['Location ID'], thePeakId);
    expect(peak.raw['Danger Warning Combat Level'], 72);
    final camp = db.activities.firstWhere((row) => row.activityId == 'ACT-0070');
    expect(camp.raw['Location ID'], giantCampId);
    expect(camp.raw['Danger Warning Combat Level'], 77);

    final save = createNewSave(db, 0);
    expect(forcedHostileActivity(db, save, thePeakId)?.activityId, 'ACT-0068');
    expect(forcedHostileActivity(db, save, giantCampId)?.activityId, 'ACT-0070');
    expect(forcedHostileActivity(db, save, theSlopesId), isNull);
  });

  test('world-map travel to Mountains lands on The Slopes', () {
    expect(
      resolveSubMapTravelDestination(db, mountainsGatewayId, mainMapId, 'LOC-0009'),
      theSlopesId,
    );
    expect(canTravelTo(db, theSlopesId, thePeakId, mountainsMapId), isTrue);
    expect(canTravelTo(db, theSlopesId, badlandsId, mountainsMapId), isTrue);
    expect(canTravelTo(db, theSlopesId, giantCampId, mountainsMapId), isTrue);
    expect(canTravelTo(db, theSlopesId, 'LOC-0036', mountainsMapId), isTrue);
  });
}
