import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/map_geometry.dart';
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

  test('the art keeps its shape on a square viewport', () {
    final rect = mapArtRect(const Size(300, 300));
    expect(rect, const Rect.fromLTWH(0, 0, 300, 300));
  });

  test('a tall viewport crops the art sideways, and nodes follow the crop', () {
    const box = Size(300, 500);
    final rect = mapArtRect(box);

    // Cover scales to the taller side, so the art hangs 100px off each edge.
    expect(rect.width, 500);
    expect(rect.height, 500);
    expect(rect.left, -100);
    expect(rect.top, 0);

    // A node halfway across the art stays halfway across the viewport, but a
    // node at the art's left edge is off screen, which is what cropping means.
    expect(mapArtOffset(const NodePosition(x: 50, y: 50), box), const Offset(150, 250));
    expect(mapArtOffset(const NodePosition(x: 0, y: 0), box), const Offset(-100, 0));
  });

  test('a wide viewport crops the art top and bottom', () {
    const box = Size(500, 300);
    final rect = mapArtRect(box);
    expect(rect.width, 500);
    expect(rect.top, -100);
    expect(mapArtOffset(const NodePosition(x: 50, y: 50), box), const Offset(250, 150));
  });

  test('an unmeasured box does not throw', () {
    expect(mapArtRect(Size.zero), const Rect.fromLTWH(0, 0, 0, 0));
  });

  test('a walking sprite sits between the two nodes', () {
    const from = NodePosition(x: 20, y: 40);
    const to = NodePosition(x: 60, y: 80);
    expect(lerpNodePosition(from, to, 0).x, 20);
    expect(lerpNodePosition(from, to, 1).y, 80);
    final middle = lerpNodePosition(from, to, 0.5);
    expect(middle.x, 40);
    expect(middle.y, 60);
  });

  test('walk duration stays inside its bounds', () {
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
