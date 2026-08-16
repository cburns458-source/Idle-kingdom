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

  test('the Citadel gateway is hidden on the citadel submap', () {
    final citadelNodes = locationsForMapView(db, citadelMapId);
    expect(citadelNodes.any((row) => row.locationId == citadelGatewayId), isFalse);
    expect(
      locationsForMapView(db, mainMapId).any((row) => row.locationId == citadelGatewayId),
      isTrue,
    );
  });

  test('west and east horizon placeholders are gone', () {
    expect(db.locations.any((row) => row.locationId == westHorizonId), isFalse);
    expect(db.locations.any((row) => row.locationId == eastHorizonId), isFalse);
  });
}
