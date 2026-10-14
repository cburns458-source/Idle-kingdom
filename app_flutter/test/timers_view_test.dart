import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

PlayerSave _readyMeadowBotany(LoadedDatabase database) {
  final base = startedCharacter(database);
  return base.copyWith(
    discoveredTimerSpotIds: const <String>['botany:LOC-0009'],
    inventory: [
      ...base.inventory,
      const InventoryStack(itemId: 'ITEM-0324', quantity: 3),
    ],
    locationTimers: <LocationTimer>[
      LocationTimer(
        locationId: 'LOC-0009',
        kind: 'botany',
        inputItemId: 'ITEM-0324',
        outputItemId: 'ITEM-0025',
        outputQuantity: 3,
        skillId: botanySkillId,
        xpReward: 10,
        startedAt: isoFromMs(testStartMs - 1000),
        durationMs: 500,
        usedCompost: true,
      ),
    ],
  );
}

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  testWidgets('Timers hides the retired Mountains gateway patch and keeps Slopes and Temple', (
    tester,
  ) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(
        discoveredTimerSpotIds: const <String>[
          'botany:LOC-0006',
          'botany:LOC-0046',
          'botany:LOC-0036',
        ],
      ),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(420, 900));

    await openChinScreen(tester, 'Timers');
    expect(find.text('Mountains'), findsNothing);
    expect(find.text('The Slopes'), findsOne);
    expect(find.text('Temple'), findsOne);
  });

  testWidgets('Timers Travel arrives instantly and opens the location stage', (tester) async {
    final controller = buildController(database, seed: _readyMeadowBotany(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(420, 900));

    expect(controller.save.currentLocationId, startingLocationId);
    await openChinScreen(tester, 'Timers');
    expect(find.text('Timers'), findsOne);
    expect(find.text('Meadow'), findsOne);

    await tester.tap(find.widgetWithText(GameButton, 'Travel'));
    await tester.pump();
    for (var i = 0; i < 20 && controller.save.currentLocationId != 'LOC-0009'; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(controller.save.currentLocationId, 'LOC-0009');
    expect(find.text('Timers'), findsNothing);
    expect(find.text('Meadow'), findsWidgets);
  });

  testWidgets('Timers Travel stays put and announces while recovering', (tester) async {
    final controller = buildController(
      database,
      seed: _readyMeadowBotany(database).copyWith(deathPauseUntil: isoFromMs(testStartMs + 30000)),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(420, 900));

    await openChinScreen(tester, 'Timers');
    await tester.tap(find.widgetWithText(GameButton, 'Travel'));
    await tester.pump();

    expect(controller.save.currentLocationId, startingLocationId);
    expect(find.text('Timers'), findsOne);
    expect(find.text(recoveringBlockedReason), findsOne);
  });

  testWidgets('collecting a patch offers to replant', (tester) async {
    final controller = buildController(database, seed: _readyMeadowBotany(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(420, 900));

    await openChinScreen(tester, 'Timers');
    await tester.tap(find.widgetWithText(GameButton, 'Travel'));
    final collect = find.text('Collect');
    await tester.pump();
    for (var i = 0; i < 20 && collect.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(collect, findsOne);
    await tester.tap(find.widgetWithText(GameButton, 'Collect'));
    await tester.pump();
    expect(find.text('Plant a seed or sapling'), findsOne);
    expect(find.text('Plant'), findsWidgets);
    expect(
      find.descendant(of: find.byKey(const Key('game-popup')), matching: find.byTooltip('Close')),
      findsOne,
    );
    expect(find.text('Close'), findsNothing);
  });

  testWidgets('auto-collect with a full bag keeps the harvest and asks for room', (tester) async {
    final controller = buildController(
      database,
      seed: _readyMeadowBotany(database).copyWith(
        inventory: [
          for (var index = 0; index < inventorySlotLimit; index++)
            InventoryStack(itemId: 'FILL-$index', quantity: 1),
        ],
      ),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(420, 900));

    await openChinScreen(tester, 'Timers');
    await tester.tap(find.widgetWithText(GameButton, 'Travel'));
    // Travel is async (hostile-check await + post-frame room alert). Pump until
    // the full-bag popup is on screen rather than racing a fixed delay.
    final roomAlert = find.text(timerInventoryFullHarvestReason);
    await tester.pump();
    for (var i = 0; i < 20 && roomAlert.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(roomAlert, findsOne);
    expect(timerAtLocationKind(controller.save, 'LOC-0009', 'botany'), isNotNull);
    // Reward popups use a Collect button. A full bag must not take the haul.
    expect(find.text('Collect'), findsNothing);
  });

  testWidgets('Timers drops a locked farm after /abandonquest and keeps a growing crop', (
    tester,
  ) async {
    const growing = LocationTimer(
      locationId: 'LOC-0001',
      kind: 'botany',
      inputItemId: 'ITEM-0324',
      outputItemId: 'ITEM-0025',
      outputQuantity: 1,
      skillId: botanySkillId,
      xpReward: 10,
      startedAt: '2026-01-01T00:00:00.000Z',
      durationMs: 60000,
    );
    final withFarm = startedCharacter(database).copyWith(
      // Stand somewhere else so the HUD title is not also "The Farm".
      currentLocationId: 'LOC-0009',
      discoveredTimerSpotIds: const <String>[
        'botany:LOC-0001',
        'botany:LOC-0009',
        'fishing_pot:LOC-0003',
      ],
      quests: const [
        QuestProgress(
          questId: 'QST-0011',
          status: 'active',
          progress: 1,
          counters: {'talk:NPC-0014': 1, 'step:QSTP-0023': 1},
        ),
      ],
    );

    final abandoned = cheatAbandonQuest(withFarm, 'QST-0011');
    expect(abandoned.ok, isTrue);
    final pruned = pruneLockedTimerSpots(database.launch, abandoned.save!);
    final emptyFarm = buildController(database, seed: pruned);
    addTearDown(emptyFarm.dispose);
    await pumpShell(tester, emptyFarm, size: const Size(420, 900));
    await openChinScreen(tester, 'Timers');
    expect(find.text('The Farm'), findsNothing);
    expect(find.text('Meadow'), findsWidgets);
    expect(find.text('Goblin Camp'), findsOne);

    await tester.pumpWidget(const SizedBox());
    final abandonedGrowing = cheatAbandonQuest(
      withFarm.copyWith(locationTimers: const [growing]),
      'QST-0011',
    );
    expect(abandonedGrowing.ok, isTrue);
    final prunedGrowing = pruneLockedTimerSpots(database.launch, abandonedGrowing.save!);
    final growingFarm = buildController(database, seed: prunedGrowing);
    addTearDown(growingFarm.dispose);
    await pumpShell(tester, growingFarm, size: const Size(420, 900));
    await openChinScreen(tester, 'Timers');
    expect(find.text('The Farm'), findsOne);
    expect(find.textContaining('Growing'), findsOne);
    expect(find.text('Meadow'), findsWidgets);
    expect(find.text('Goblin Camp'), findsOne);
  });
}
