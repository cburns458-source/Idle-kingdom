import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = assertGameDatabaseShape(contentDatabaseJson());
  });

  test('submap gateways use Map Node Name on the child map', () {
    final town = db.locations.firstWhere((row) => row.locationId == townGatewayId);
    expect(mapNodeLabel(town, townMapId), 'Town Gate');
    expect(mapNodeLabel(town, mainMapId), 'The Town');

    final castle = db.locations.firstWhere((row) => row.locationId == castleGatewayId);
    expect(mapNodeLabel(castle, castleMapId), 'Castle Gate');
    expect(mapNodeLabel(castle, mainMapId), 'Castle');
  });

  test('submap interiors offer a back label and gateways do not', () {
    final kitchen = db.locations.firstWhere((row) => row.locationId == townKitchenId);
    expect(backToSubMapLabel(db, kitchen), 'Back to Town');
    expect(enterSubMapLabel(db, kitchen), isNull);

    final town = db.locations.firstWhere((row) => row.locationId == townGatewayId);
    expect(backToSubMapLabel(db, town), isNull);
    expect(enterSubMapLabel(db, town), 'Enter Town');

    final plaza = db.locations.firstWhere((row) => row.locationId == citadelPlazaId);
    expect(backToSubMapLabel(db, plaza), 'Back to Citadel');

    final farm = db.locations.firstWhere((row) => row.locationId == 'LOC-0001');
    expect(backToSubMapLabel(db, farm), isNull);
  });

  test('submap gateways stay on the world map and hide on their child maps', () {
    expect(
      locationsForMapView(db, townMapId).any((row) => row.locationId == townGatewayId),
      isFalse,
    );
    expect(
      locationsForMapView(db, caveMapId).any((row) => row.locationId == caveEntranceId),
      isFalse,
    );
    expect(
      locationsForMapView(db, castleMapId).any((row) => row.locationId == castleGatewayId),
      isFalse,
    );
    expect(
      locationsForMapView(db, citadelMapId).any((row) => row.locationId == citadelGatewayId),
      isFalse,
    );
    expect(
      locationsForMapView(db, mainMapId).any((row) => row.locationId == townGatewayId),
      isTrue,
    );
    expect(
      locationsForMapView(db, mainMapId).any((row) => row.locationId == citadelGatewayId),
      isTrue,
    );
  });

  test('world-map travel to a gateway lands on the written child-map node', () {
    expect(
      landingLocationIdFor(db.locations.firstWhere((row) => row.locationId == townGatewayId)),
      townGeneralStoreId,
    );
    expect(
      landingLocationIdFor(db.locations.firstWhere((row) => row.locationId == caveEntranceId)),
      caveMiningStoreId,
    );
    expect(
      landingLocationIdFor(db.locations.firstWhere((row) => row.locationId == castleGatewayId)),
      castleCourtyardId,
    );
    expect(
      landingLocationIdFor(db.locations.firstWhere((row) => row.locationId == citadelGatewayId)),
      citadelPlazaId,
    );
    expect(
      resolveSubMapTravelDestination(db, townGatewayId, mainMapId, 'LOC-0009'),
      townGeneralStoreId,
    );
    expect(
      resolveSubMapTravelDestination(db, townGeneralStoreId, townMapId, townKitchenId),
      townGeneralStoreId,
    );
  });

  test('west and east horizon placeholders are gone', () {
    expect(db.locations.any((row) => row.locationId == westHorizonId), isFalse);
    expect(db.locations.any((row) => row.locationId == eastHorizonId), isFalse);
  });
}
