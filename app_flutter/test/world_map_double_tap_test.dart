import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/ui/world_map_view.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  testWidgets('a second tap inside the 300 ms window travels; outside it only selects', (
    tester,
  ) async {
    final allIds = <String>[for (final row in database.launch.locations) row.locationId];
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(unlockedLocationIds: allIds),
    );
    addTearDown(controller.dispose);

    var now = DateTime.utc(2026, 1, 1);
    final selected = <String>[];
    final travelled = <String>[];

    await pumpPanel(
      tester,
      WorldMapView(
        controller: controller,
        browseMapId: mainMapId,
        selectedLocationId: null,
        onSelect: selected.add,
        onBrowseMap: (_) {},
        onTravel: travelled.add,
        now: () => now,
      ),
      size: const Size(420, 900),
    );
    await tester.pump();

    final meadow = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'Meadow' && w.properties.button == true,
    );
    expect(meadow, findsOne);

    Future<void> tapMeadow() async {
      await tester.tap(meadow);
      await tester.pump();
    }

    await tapMeadow();
    expect(selected, ['LOC-0009']);
    expect(travelled, isEmpty);

    now = now.add(const Duration(milliseconds: 299));
    await tapMeadow();
    expect(selected, ['LOC-0009']);
    expect(travelled, ['LOC-0009']);

    selected.clear();
    travelled.clear();
    now = now.add(const Duration(seconds: 1));
    await tapMeadow();
    expect(selected, ['LOC-0009']);
    expect(travelled, isEmpty);

    now = now.add(const Duration(milliseconds: 301));
    await tapMeadow();
    expect(selected, ['LOC-0009', 'LOC-0009']);
    expect(travelled, isEmpty);

    selected.clear();
    travelled.clear();
    now = now.add(const Duration(seconds: 1));
    await tapMeadow();
    expect(selected, ['LOC-0009']);
    expect(travelled, isEmpty);

    now = now.add(worldMapDoubleTapWindow);
    await tapMeadow();
    expect(selected, ['LOC-0009']);
    expect(travelled, ['LOC-0009']);
  });
}
