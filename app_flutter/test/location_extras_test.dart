import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/ui/critter_overlay.dart';
import 'package:idle_kingdoms/src/ui/pixel_chrome.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  /// The tile itself, not the row it is aligned inside, which is what a tap has
  /// to land on.
  final critterTile = find.descendant(
    of: find.byType(CritterOverlay),
    matching: find.byType(InkWell),
  );

  group('the critter overlay', () {
    /// At the Farm, where the Fly lives, with one already waiting.
    PlayerSave withFlyWaiting() {
      return startedCharacter(database).copyWith(
        currentLocationId: 'LOC-0001',
        activeCritterSpawns: <CritterSpawn>[
          CritterSpawn(
            locationId: 'LOC-0001',
            critterId: 'CRT-0001',
            appearedAt: isoFromMs(testStartMs),
          ),
        ],
      );
    }

    testWidgets('collects what is waiting and says so', (tester) async {
      final controller = buildController(database, seed: withFlyWaiting());
      addTearDown(controller.dispose);
      await pumpShell(tester, controller);

      expect(find.bySemanticsLabel('Collect Fly'), findsOne);
      await tester.tap(critterTile);
      await tester.pump();

      expect(collectionCount(controller.save, 'CRT-0001'), 1);
      expect(activeSpawnAtLocation(controller.save, 'LOC-0001'), isNull);
      expect(find.text('Collected Fly!'), findsOne);
      expect(critterTile, findsNothing);
    });

    testWidgets('counts a repeat catch', (tester) async {
      final controller = buildController(
        database,
        seed: withFlyWaiting().copyWith(
          critterCollections: const <CritterCollectionEntry>[
            CritterCollectionEntry(critterId: 'CRT-0001', count: 2),
          ],
        ),
      );
      addTearDown(controller.dispose);
      await pumpShell(tester, controller);

      await tester.tap(critterTile);
      await tester.pump();

      expect(collectionCount(controller.save, 'CRT-0001'), 3);
      expect(find.text('Collected Fly (×3).'), findsOne);
    });

    testWidgets('stays away when nothing is waiting', (tester) async {
      final controller = buildController(
        database,
        seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0001'),
      );
      addTearDown(controller.dispose);
      await pumpShell(tester, controller);

      expect(critterTile, findsNothing);
    });
  });

  group('the auto-equip prompt', () {
    /// In the meadow with a hunting net in the bag but nothing in hand, which is
    /// what the hunting activity there refuses over.
    PlayerSave withNetInBag() {
      return startedCharacter(database).copyWith(
        currentLocationId: 'LOC-0009',
        inventory: <InventoryStack>[
          ...startedCharacter(database).inventory,
          const InventoryStack(itemId: 'ITEM-0108', quantity: 1),
        ],
      );
    }

    Future<void> tapHunt(WidgetTester tester) async {
      // The hunting activity here is the one the starter kit cannot do.
      final card = find.ancestor(
        of: find.text('Search for small game'),
        matching: find.byType(PixelFill),
      );
      await tapVisible(tester, find.descendant(of: card, matching: find.bySemanticsLabel('Start')));
    }

    testWidgets('offers the tool the bag already holds', (tester) async {
      final controller = buildController(database, seed: withNetInBag());
      addTearDown(controller.dispose);
      await pumpShell(tester, controller);

      await tapHunt(tester);

      expect(find.text('Equip required tool?'), findsOne);
      expect(find.textContaining('Equip Net (hunting tool)'), findsOne);
    });

    testWidgets('equips and starts on confirm', (tester) async {
      final controller = buildController(database, seed: withNetInBag());
      addTearDown(controller.dispose);
      await pumpShell(tester, controller);
      await tapHunt(tester);

      await tester.tap(find.text('Equip & Start'));
      await tester.pump();

      expect(slotStack(controller.save, 'SLOT-0001')?.itemId, 'ITEM-0108');
      expect(controller.save.currentActivityId, 'ACT-0011');
      expect(find.text('Equip required tool?'), findsNothing);
    });

    testWidgets('leaves the refusal on screen when turned down', (tester) async {
      final controller = buildController(database, seed: withNetInBag());
      addTearDown(controller.dispose);
      await pumpShell(tester, controller);
      await tapHunt(tester);

      await tester.tap(find.text('Not now'));
      await tester.pump();

      expect(find.text('Equip required tool?'), findsNothing);
      expect(controller.save.currentActivityId, isNull);
      expect(controller.activityError, isNotNull);
    });

    testWidgets('says why when the bag has no tool to offer', (tester) async {
      final controller = buildController(
        database,
        seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
      );
      addTearDown(controller.dispose);
      await pumpShell(tester, controller);

      await tapHunt(tester);

      expect(find.text('Equip required tool?'), findsNothing);
      expect(controller.activityError, isNotNull);
    });
  });
}
