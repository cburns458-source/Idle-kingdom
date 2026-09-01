import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/ui/critter_overlay.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/action_stage.dart';
import 'package:idle_kingdoms/src/ui/location_view.dart';
import 'package:idle_kingdoms/src/ui/overlay_notice.dart';
import 'package:idle_kingdoms/src/ui/shop_panel.dart';
import 'package:idle_kingdoms/src/ui/world_map_view.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  testWidgets('a location and its activities show no blurbs', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.text('Meadow'), findsWidgets);
    expect(find.text('Gather meadow supplies'), findsWidgets);
    expect(find.text('Small-game Hunting and Harvesting area.'), findsNothing);
    expect(find.text('Wild Roots and Fernleaf Harvesting.'), findsNothing);
  });

  Future<void> pumpLocation(WidgetTester tester, String locationId) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: locationId),
    );
    addTearDown(controller.dispose);
    await pumpPanel(
      tester,
      LocationView(
        controller: controller,
        multiplayer: buildMultiplayer(database),
        onOpenMap: () {},
      ),
      size: const Size(900, 2400),
    );
  }

  testWidgets('Goblin Camp still shows the location danger line and activity warning', (
    tester,
  ) async {
    await pumpLocation(tester, 'LOC-0003');
    expect(find.text('Goblin Camp'), findsWidgets);
    expect(find.text('Danger warning: approximately Combat Level 10.'), findsOne);
    expect(find.text('Combat warning ~ Level 10'), findsOne);
  });

  testWidgets('hostile docks, quarters, and crypt still name their danger', (tester) async {
    await pumpLocation(tester, 'LOC-0004');
    expect(find.text('Pirate encounters can occur.'), findsOne);

    await pumpLocation(tester, 'LOC-0021');
    expect(find.text('A dragon guards the Queen.'), findsOne);

    await pumpLocation(tester, 'LOC-0037');
    expect(find.text('The old spirits still linger.'), findsOne);
  });

  testWidgets('Old Ent Grove hides the location danger line', (tester) async {
    await pumpLocation(tester, 'LOC-0018');
    expect(find.text('Old Ent Grove'), findsWidgets);
    expect(find.text('Includes Ent Combat encounters.'), findsNothing);
  });

  testWidgets('Wizard\'s Tower hides the location danger line', (tester) async {
    await pumpLocation(tester, 'LOC-0007');
    expect(find.text('Wizard\'s Tower'), findsWidgets);
    expect(find.text('Contains Skeleton and Zombie Combat Actions.'), findsNothing);
  });

  testWidgets('the map panel names a place without describing it', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.tap(find.byTooltip('Open world map'));
    await tester.pump();
    await tester.tap(find.text('The Farm'));
    await tester.pump();

    expect(find.text('The Farm'), findsWidgets);
    expect(find.text('Pasture-focused starting area with Cow and Bull encounters.'), findsNothing);
    expect(
      find.descendant(of: find.byType(WorldMapView), matching: find.byTooltip('Combat')),
      findsOne,
    );
    expect(
      find.descendant(of: find.byType(WorldMapView), matching: find.byTooltip('Harvesting')),
      findsOne,
    );
  });

  testWidgets('OverlayNotice dismisses after its hold', (tester) async {
    var dismissed = false;
    const text = 'Requires equipped hunting tool';
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: OverlayNotice(text: text, tone: Palette.danger, onDismissed: () => dismissed = true),
      ),
    );
    expect(find.byType(OverlayNotice), findsOne);

    await tester.pump(noticeHoldDuration(text));
    await tester.pump();
    await tester.pump(noticeFadeDuration);
    await tester.pump();

    expect(dismissed, isTrue);
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
        matching: find.byType(DockRow),
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

    PlayerSave startedWithoutNet() {
      final save = startedCharacter(database);
      return save.copyWith(
        currentLocationId: 'LOC-0009',
        inventory: save.inventory.where((stack) => stack.itemId != 'ITEM-0108').toList(),
      );
    }

    testWidgets('says why when the bag has no tool to offer', (tester) async {
      final controller = buildController(database, seed: startedWithoutNet());
      addTearDown(controller.dispose);
      await pumpShell(tester, controller);

      await tapHunt(tester);

      expect(find.text('Equip required tool?'), findsNothing);
      expect(controller.activityError, isNotNull);
    });

    testWidgets('arriving at a favorited hunt offers Equip & Start', (tester) async {
      final base = startedCharacter(database);
      final controller = buildController(
        database,
        seed: base.copyWith(
          currentLocationId: 'LOC-0001',
          favoriteActivityByLocationId: const {'LOC-0009': 'ACT-0011'},
          inventory: <InventoryStack>[
            ...base.inventory,
            const InventoryStack(itemId: 'ITEM-0108', quantity: 1),
          ],
        ),
      );
      controller.setMapTravelAnimation(false);
      addTearDown(controller.dispose);
      await pumpShell(tester, controller);

      expect(controller.autoEquip, isNull);
      expect(controller.travelTo('LOC-0009', mainMapId), isTrue);
      await tester.pump();

      expect(controller.save.currentLocationId, 'LOC-0009');
      expect(controller.save.currentActivityId, isNull);
      expect(find.text('Equip required tool?'), findsOne);
      expect(find.text('Equip & Start'), findsOne);
    });

    testWidgets('a refusal floats over the dock and fades away', (tester) async {
      final controller = buildController(database, seed: startedWithoutNet());
      addTearDown(controller.dispose);
      await pumpShell(tester, controller);

      await tapHunt(tester);

      final reason = controller.activityError!;
      expect(find.byType(OverlayNotice), findsOne);
      expect(
        find.descendant(of: find.byType(OverlayNotice), matching: find.text(reason)),
        findsOne,
      );
      expect(
        find.descendant(of: find.byType(DockRow), matching: find.byType(OverlayNotice)),
        findsNothing,
      );

      await tester.pump(noticeHoldDuration(reason));
      await tester.pump();
      await tester.pump(noticeFadeDuration);
      await tester.pump();

      expect(find.byType(OverlayNotice), findsNothing);
      expect(controller.activityError, isNull);
    });
  });

  testWidgets('travelling to Town from the world map opens the town map at the store', (
    tester,
  ) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.text('Enter Town'), findsNothing);
    expect(find.byTooltip('Back to Town'), findsNothing);

    await tester.tap(find.byTooltip('Open world map'));
    await tester.pump();
    await tester.tap(find.text('The Town'));
    await tester.pump();
    await tester.tap(find.text('Travel'));
    await tester.pump();

    expect(controller.save.currentLocationId, townGeneralStoreId);
    expect(find.byType(WorldMapView), findsOne);
    expect(
      find.descendant(of: find.byType(WorldMapView), matching: find.text('Kitchen')),
      findsWidgets,
    );
    expect(
      find.descendant(of: find.byType(WorldMapView), matching: find.text('General Store')),
      findsWidgets,
    );
    expect(find.text('Town Gate'), findsNothing);
    expect(find.text('You are here.'), findsOne);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    expect(find.byType(WorldMapView), findsNothing);
    expect(find.byTooltip('Back to Town'), findsOne);
  });

  testWidgets('the town map chip returns to the world map without moving', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: townKitchenId),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.tap(find.byTooltip('Back to Town'));
    await tester.pump();
    expect(find.byType(WorldMapView), findsOne);
    expect(find.text('Town Gate'), findsNothing);

    await tester.tap(
      find.descendant(of: find.byType(WorldMapView), matching: find.byTooltip('Open world map')),
    );
    await tester.pump();

    expect(find.text('The Farm'), findsOne);
    expect(controller.save.currentLocationId, townKitchenId);
  });

  testWidgets('shop map nodes show a coin, other nodes do not', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: townKitchenId),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.tap(find.byTooltip('Back to Town'));
    await tester.pump();

    Finder nodeOf(String label) {
      return find.ancestor(
        of: find.descendant(of: find.byType(WorldMapView), matching: find.text(label)).first,
        matching: find.byType(GestureDetector),
      );
    }

    expect(
      find.descendant(of: find.byType(WorldMapView), matching: find.text('General Store')),
      findsWidgets,
    );
    expect(
      find.descendant(of: nodeOf('General Store'), matching: find.byTooltip('Shop')),
      findsOne,
    );
    expect(find.descendant(of: nodeOf('Kitchen'), matching: find.byTooltip('Shop')), findsNothing);
  });

  testWidgets('Enter on a gateway opens the submap at its landing', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: townGatewayId),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.text('Enter Town'), findsOne);
    await tester.tap(find.text('Enter Town'));
    await tester.pump();

    expect(controller.save.currentLocationId, townGeneralStoreId);
    expect(find.byType(WorldMapView), findsOne);
    expect(
      find.descendant(of: find.byType(WorldMapView), matching: find.text('General Store')),
      findsWidgets,
    );
    expect(find.text('You are here.'), findsOne);
  });

  testWidgets('Enter Forest Gate opens the Ancient Forest at Forest Path', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: forestGatewayId),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.text('Forest Gate'), findsWidgets);
    expect(find.text('Enter Ancient Forest'), findsOne);
    await tester.tap(find.text('Enter Ancient Forest'));
    await tester.pump();

    expect(controller.save.currentLocationId, forestPathId);
    expect(find.byType(WorldMapView), findsOne);
    expect(
      find.descendant(of: find.byType(WorldMapView), matching: find.text('Forest Path')),
      findsWidgets,
    );
    expect(
      find.descendant(of: find.byType(WorldMapView), matching: find.text('Old Ent Grove')),
      findsWidgets,
    );
    expect(find.text('Forest Gate'), findsNothing);
  });

  testWidgets('Enter Sunken Approach opens The Shallows', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: sunkenApproachId),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.text('Sunken Approach'), findsWidgets);
    expect(find.text('Enter The Depths'), findsOne);
    await tester.tap(find.text('Enter The Depths'));
    await tester.pump();

    expect(controller.save.currentLocationId, theShallowsId);
    expect(find.byType(WorldMapView), findsOne);
    expect(
      find.descendant(of: find.byType(WorldMapView), matching: find.text('The Shallows')),
      findsWidgets,
    );
    expect(find.text('Sunken Approach'), findsNothing);
  });

  testWidgets('the town map shows district nodes and hides the entrance', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: townKitchenId),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.tap(find.byTooltip('Back to Town'));
    await tester.pump();

    expect(find.byType(WorldMapView), findsOne);
    expect(
      find.descendant(of: find.byType(WorldMapView), matching: find.text('Kitchen')),
      findsWidgets,
    );
    expect(
      find.descendant(of: find.byType(WorldMapView), matching: find.text('General Store')),
      findsOne,
    );
    expect(find.text('Town Gate'), findsNothing);
  });

  testWidgets('travelling between town nodes still opens the location page', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: townKitchenId),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.tap(find.byTooltip('Back to Town'));
    await tester.pump();
    await tester.tap(find.text('General Store'));
    await tester.pump();
    await tester.tap(find.text('Travel'));
    await tester.pump();

    expect(controller.save.currentLocationId, townGeneralStoreId);
    expect(find.byType(WorldMapView), findsNothing);
    expect(find.byTooltip('Back to Town'), findsOne);
  });

  testWidgets('the workshop lists Special production as its own tab', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0025'),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.widgetWithText(GameButton, 'Special production'), findsOne);
    expect(find.text('Special production'), findsOne);
  });

  testWidgets('the option band shows one tab per group at the kitchen', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0023'),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.widgetWithText(GameButton, 'Activities'), findsOne);
    expect(find.widgetWithText(GameButton, 'People'), findsOne);
    expect(find.text('Cook at the kitchen'), findsOne);
    expect(find.text('Rose'), findsNothing);

    await tester.tap(find.widgetWithText(GameButton, 'People'));
    await tester.pump();
    expect(find.text('Rose'), findsOne);
    expect(find.text('Cook at the kitchen'), findsNothing);
  });

  testWidgets('expanding the option list does not carry to the next location', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
    );
    controller.setMapTravelAnimation(false);
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tapVisible(tester, find.byTooltip('Expand list'));
    expect(find.byTooltip('Collapse list'), findsOne);

    controller.commit(controller.save.copyWith(currentLocationId: 'LOC-0001'));
    await tester.pump();

    expect(controller.save.currentLocationId, 'LOC-0001');
    expect(find.byTooltip('Expand list'), findsOne);
    expect(find.byTooltip('Collapse list'), findsNothing);
  });

  testWidgets('Quill stands only at today’s shared stop', (tester) async {
    final today = quillLocationId(testStartMs);
    for (final locationId in quillRoute) {
      final controller = buildController(
        database,
        seed: startedCharacter(database).copyWith(currentLocationId: locationId),
      );
      addTearDown(controller.dispose);
      await pumpPanel(
        tester,
        LocationView(
          controller: controller,
          multiplayer: buildMultiplayer(database),
          onOpenMap: () {},
        ),
        size: const Size(900, 2400),
      );
      final people = find.widgetWithText(GameButton, 'People');
      if (people.evaluate().isNotEmpty) {
        await tester.tap(people);
        await tester.pump();
      }
      expect(find.text('Quill'), locationId == today ? findsOne : findsNothing);
    }
  });

  testWidgets('the Master Dwarf stands only at today’s shared stop', (tester) async {
    final today = masterDwarfLocationId(testStartMs);
    for (final locationId in masterDwarfRoute) {
      final controller = buildController(
        database,
        seed: startedCharacter(database).copyWith(currentLocationId: locationId),
      );
      addTearDown(controller.dispose);
      await pumpPanel(
        tester,
        LocationView(
          controller: controller,
          multiplayer: buildMultiplayer(database),
          onOpenMap: () {},
        ),
        size: const Size(900, 2400),
      );
      final people = find.widgetWithText(GameButton, 'People');
      if (people.evaluate().isNotEmpty) {
        await tester.tap(people);
        await tester.pump();
      }
      expect(find.text('Master Dwarf'), locationId == today ? findsOne : findsNothing);
    }
  });

  testWidgets('a shop overlays a running fight instead of sharing the band', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0032'),
    );
    addTearDown(controller.dispose);
    await pumpPanel(
      tester,
      ListenableBuilder(
        listenable: controller,
        builder: (context, _) => LocationView(
          controller: controller,
          multiplayer: buildMultiplayer(database),
          onOpenMap: () {},
        ),
      ),
      size: const Size(900, 2400),
    );

    Finder dockRow(String title) {
      return find.ancestor(of: find.text(title), matching: find.byType(DockRow));
    }

    await tapVisible(
      tester,
      find.descendant(
        of: dockRow('Challenge the guards'),
        matching: find.bySemanticsLabel('Start'),
      ),
    );
    expect(controller.save.currentActivityId, isNotNull);
    expect(find.byType(ActionStage), findsOne);

    await tester.tap(find.widgetWithText(GameButton, 'Shops'));
    await tester.pump();
    await tapVisible(
      tester,
      find.descendant(of: dockRow('Armory'), matching: find.widgetWithText(GameButton, 'Shop')),
    );
    expect(find.byType(ActionStage), findsOne);
    expect(find.byType(ShopPanel), findsOne);

    final stage = tester.getRect(find.byType(ActionStage));
    final shop = tester.getRect(find.byType(ShopPanel));
    expect(shop.overlaps(stage), isTrue);
    expect(shop.height, greaterThan(200));
  });
}
