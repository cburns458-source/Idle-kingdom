import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/world_map_view.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

/// The real game font, so the label measure and the drawn glyphs are the ones
/// a phone shows rather than the test harness's placeholder font.
Future<void> _loadGameFont() async {
  final file = File('fonts/PixeloidSans.ttf');
  expect(file.existsSync(), isTrue, reason: 'fonts/PixeloidSans.ttf is bundled with the app');
  final loader = FontLoader(gameFontFamily);
  loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  await loader.load();
}

/// Every word of [label] as it is drawn by [paragraph], with the line tops it
/// landed on. A word on one line has exactly one distinct top.
Map<String, Set<int>> _wordLineTops(RenderParagraph paragraph, String label) {
  final tops = <String, Set<int>>{};
  var start = 0;
  for (final word in label.split(' ')) {
    if (word.isNotEmpty) {
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + word.length),
      );
      tops[word] = {for (final box in boxes) box.top.round()};
    }
    start += word.length + 1;
  }
  return tops;
}

void main() {
  late LoadedDatabase database;

  setUpAll(() async {
    database = loadDatabaseFromRepo();
    await _loadGameFont();
  });

  test('the label style names the game font so measure and draw agree', () {
    expect(mapNodeLabelStyle.fontFamily, gameFontFamily);
  });

  const size = Size(360, 640);
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

  for (final mapId in maps) {
    testWidgets('$mapId labels never break inside a word at 360px', (tester) async {
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
      final labels = [for (final node in nodes) mapNodeLabel(node, mapId)];
      if (mapId == mainMapId) {
        expect(labels, contains('Kingswoods'), reason: 'the widest one-word name is on the map');
      }

      var checked = 0;
      for (final label in labels) {
        final finder = find.byWidgetPredicate(
          (w) => w is Text && w.data == label && w.style == mapNodeLabelStyle,
        );
        if (finder.evaluate().isEmpty) continue;
        final paragraph = tester.renderObject<RenderParagraph>(finder.first);
        expect(paragraph.didExceedMaxLines, isFalse, reason: '$label was cut short');
        final tops = _wordLineTops(paragraph, label);
        for (final entry in tops.entries) {
          expect(
            entry.value,
            hasLength(1),
            reason: '"${entry.key}" in "$label" is split across lines ${entry.value}',
          );
        }
        if (!label.contains(' ')) {
          // The measured box has to hold the word at full size; shrinking to
          // fit is only the fallback.
          final box = find.ancestor(of: finder.first, matching: find.byType(SizedBox));
          expect(
            paragraph.size.width,
            lessThanOrEqualTo(tester.getSize(box.first).width),
            reason: '$label had to shrink to fit its box',
          );
        }
        checked++;
      }
      expect(checked, greaterThan(0));
    });
  }
}
