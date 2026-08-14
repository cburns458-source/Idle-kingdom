import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/map_walk.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  test('same-map walks start on the node the player is standing on', () {
    expect(mapWalkStartLocationId(database.launch, 'LOC-0009', mainMapId), 'LOC-0009');
  });

  test('a walk off a district starts at that map\'s entrance', () {
    expect(mapWalkStartLocationId(database.launch, 'LOC-0023', mainMapId), townGatewayId);
    expect(mapWalkStartLocationId(database.launch, 'LOC-0028', mainMapId), citadelGatewayId);
  });

  test('walk duration stays between one and three seconds', () {
    const near = NodePosition(x: 16, y: 58);
    const far = NodePosition(x: 76, y: 66);
    const same = NodePosition(x: 50, y: 50);
    expect(mapWalkDurationMs(same, same), mapWalkMinMs);
    final across = mapWalkDurationMs(near, far);
    expect(across, greaterThan(mapWalkMinMs));
    expect(across, lessThanOrEqualTo(mapWalkMaxMs));
    expect(
      mapWalkDurationMs(const NodePosition(x: 0, y: 0), const NodePosition(x: 100, y: 100)),
      mapWalkMaxMs,
    );
  });
}
