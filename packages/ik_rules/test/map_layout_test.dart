import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = filterLaunchContent(assertGameDatabaseShape(contentDatabaseJson()));
  });

  test('MapNodes match the hardcoded fallback layouts', () {
    const mapIds = <String>[
      mainMapId,
      caveMapId,
      castleMapId,
      townMapId,
      citadelMapId,
      forestMapId,
      depthsMapId,
    ];
    for (final mapId in mapIds) {
      final hardcoded = layoutForMap(mapId);
      final fromDb = layoutForMap(mapId, db);
      expect(fromDb.keys.toSet(), hardcoded.keys.toSet(), reason: mapId);
      for (final locationId in hardcoded.keys) {
        expect(fromDb[locationId]!.x, hardcoded[locationId]!.x, reason: '$mapId $locationId x');
        expect(fromDb[locationId]!.y, hardcoded[locationId]!.y, reason: '$mapId $locationId y');
      }
    }
  });

  test('every launch location on a laid-out map has a MapNode', () {
    final nodeKeys = {for (final row in mapNodesOf(db)) '${row['Map ID']}|${row['Location ID']}'};
    for (final location in db.locations) {
      if (isFutureHorizonLocation(location.locationId)) continue;
      final mapId = location.mapId;
      if (mapId == null || isFutureRegionMapId(mapId)) continue;
      if (layoutForMap(mapId).isEmpty) continue;
      expect(
        nodeKeys.contains('$mapId|${location.locationId}'),
        isTrue,
        reason: '${location.locationId} on $mapId',
      );
    }
  });
}
