import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

PlayerSave _readyMeadowBotany(LoadedDatabase database) {
  return startedCharacter(database).copyWith(
    discoveredTimerSpotIds: const <String>['botany:LOC-0009'],
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
      ),
    ],
  );
}

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
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
    await tester.pump(const Duration(milliseconds: 300));

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
}
