import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

GameDatabase _db() => filterLaunchContent(assertGameDatabaseShape(contentDatabaseJson()));

void main() {
  final db = _db();
  final gateways = db.locations.where(isSubMapGateway).toList();

  test('finds Launch gateways', () {
    expect(gateways, isNotEmpty);
  });

  for (final gate in gateways) {
    test('${gate.locationId} lands on a node of its own sub-map, open from the start', () {
      final subMapId = subMapIdForGateway(db, gate.locationId);
      expect(subMapId, isNotNull);
      expect(gate.raw['Map ID'], mainMapId);
      final landingId = landingLocationIdFor(gate);
      expect(landingId, isNotNull);
      if (landingId == null) return;
      final landing = db.locations.firstWhere((row) => row.locationId == landingId);
      expect(landing.raw['Map ID'], subMapId);
      expect(landing.raw['Parent Location ID'], gate.locationId);
      expect(locationsForMapView(db, subMapId!).any((row) => row.locationId == landingId), isTrue);
    });
  }

  for (final gate in gateways) {
    test('${gate.locationId} is hidden on its own sub-map', () {
      final subMapId = subMapIdForGateway(db, gate.locationId)!;
      expect(
        locationsForMapView(db, subMapId).any((row) => row.locationId == gate.locationId),
        isFalse,
      );
    });
  }

  test('covers the #313 landings: Town Square and Cave Mouth', () {
    final landings = gateways.map(landingLocationIdFor).toList();
    expect(landings, contains(townSquareId));
    expect(landings, contains(caveMouthId));
  });
}
