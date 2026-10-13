import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/map_geometry.dart';
import 'package:idle_kingdoms/src/session/map_walk.dart';
import 'package:idle_kingdoms/src/ui/world_map_view.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  group('clampCentredLeft', () {
    test('a label with room stays centred on its dot', () {
      expect(clampCentredLeft(160, 80, 320), 120);
    });

    test('a label near the right edge slides in to the margin', () {
      // x84 on a 320px 9:16 plate lands near 269px.
      final left = clampCentredLeft(269, 100, 320);
      expect(left + 100, lessThanOrEqualTo(320 - mapLabelEdgeMargin));
      expect(left, 216);
    });

    test('a label near the left edge slides in to the margin', () {
      expect(clampCentredLeft(10, 80, 320), mapLabelEdgeMargin);
    });

    test('a label wider than the view is centred in it', () {
      expect(clampCentredLeft(300, 400, 320), -40);
    });

    test('the label cap narrows on small phones', () {
      expect(mapLabelMaxWidth(320), 120);
      expect(mapLabelMaxWidth(200), 80);
      expect(mapLabelMaxWidth(100), 64);
    });
  });

  const maps = <String>[
    mainMapId,
    townMapId,
    castleMapId,
    caveMapId,
    citadelMapId,
    forestMapId,
    depthsMapId,
    mountainsMapId,
  ];
  const sizes = <Size>[Size(320, 568), Size(360, 640)];

  for (final size in sizes) {
    for (final mapId in maps) {
      testWidgets(
        '$mapId labels stay inside a ${size.width.toInt()}px view and dots stay on landmarks',
        (tester) async {
          final allIds = [for (final row in database.launch.locations) row.locationId];
          final controller = buildController(
            database,
            seed: startedCharacter(database).copyWith(unlockedLocationIds: allIds),
          );
          addTearDown(controller.dispose);
          await pumpPanel(
            tester,
            WorldMapView(
              controller: controller,
              browseMapId: mapId,
              selectedLocationId: null,
              onSelect: (_) {},
              onBrowseMap: (_) {},
              onTravel: (_) {},
            ),
            size: size,
          );
          await tester.pump();

          final nodes = locationsForMapView(
            controller.db,
            mapId,
            controller.save.unlockedLocationIds,
            const <String>[],
            controller.save.currentLocationId,
            controller.save,
          );
          final view = tester.getRect(find.byType(WorldMapView));
          final aspect = artAspectRatioForMap(mapId);
          var checked = 0;
          for (final node in nodes) {
            final label = mapNodeLabel(node, mapId);
            final labelFinder = find.byWidgetPredicate(
              (w) => w is Text && w.data == label && w.style == mapNodeLabelStyle,
            );
            if (labelFinder.evaluate().isEmpty) continue;
            final labelRect = tester.getRect(labelFinder.first);
            expect(labelRect.left, greaterThanOrEqualTo(view.left), reason: '$label left');
            expect(labelRect.right, lessThanOrEqualTo(view.right), reason: '$label right');

            final dot = tester.getRect(
              find
                  .byWidgetPredicate(
                    (w) =>
                        w is Semantics &&
                        w.properties.label == label &&
                        w.properties.button == true,
                  )
                  .first,
            );
            final expected = mapArtOffset(
              positionOnBrowseMap(node.locationId, mapId, node, controller.db),
              view.size,
              aspectRatio: aspect,
            );
            expect(
              (dot.center.dx - view.left - expected.dx).abs(),
              lessThanOrEqualTo(1),
              reason: '$label dot x',
            );
            expect(
              (dot.top + mapNodeDotCenter - view.top - expected.dy).abs(),
              lessThanOrEqualTo(1),
              reason: '$label dot y',
            );
            checked++;
          }
          expect(checked, greaterThan(0));
        },
      );
    }
  }
}
