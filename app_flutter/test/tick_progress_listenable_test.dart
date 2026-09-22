import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ik_content/ik_content.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  test('quiet ticks notify progress without rebuilding the shell listenable', () {
    final clock = TestClock();
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
      clock: clock,
    );
    addTearDown(controller.dispose);

    var shellNotifies = 0;
    var progressNotifies = 0;
    controller.addListener(() => shellNotifies++);
    controller.progress.addListener(() => progressNotifies++);

    clock.advance(16);
    controller.tick();
    clock.advance(16);
    controller.tick();
    clock.advance(16);
    controller.tick();

    expect(progressNotifies, 1);
    expect(shellNotifies, 0);
  });

  test('a still location notifies progress four times a second, not sixty', () {
    final clock = TestClock();
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
      clock: clock,
    );
    addTearDown(controller.dispose);

    var progressNotifies = 0;
    controller.progress.addListener(() => progressNotifies++);

    // A second of frames at 60fps.
    for (var frame = 0; frame < 60; frame += 1) {
      clock.advance(16);
      controller.tick();
    }

    expect(controller.framePacedOnScreen, isFalse);
    expect(progressNotifies, 4);
  });

  test('a running activity notifies progress on every frame', () {
    final clock = TestClock();
    final controller = buildController(database, seed: startedCharacter(database), clock: clock);
    addTearDown(controller.dispose);
    final activity = database.launch.activities.firstWhere(
      (row) => row.locationId == controller.save.currentLocationId,
    );
    controller.startActivity(activity.activityId);

    var progressNotifies = 0;
    controller.progress.addListener(() => progressNotifies++);
    for (var frame = 0; frame < 10; frame += 1) {
      clock.advance(16);
      controller.tick();
    }

    expect(controller.framePacedOnScreen, isTrue);
    expect(progressNotifies, 10);
  });

  test('anything the player did comes through without waiting out the quiet gap', () {
    final clock = TestClock();
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
      clock: clock,
    );
    addTearDown(controller.dispose);

    clock.advance(16);
    controller.tick();
    var progressNotifies = 0;
    controller.progress.addListener(() => progressNotifies++);

    // Gold in hand is a save change, so the bar it feeds refreshes on the frame
    // it happens rather than up to a quarter second later.
    controller.commit(controller.save.copyWith(gold: controller.save.gold + 10));
    clock.advance(16);
    controller.tick();

    expect(progressNotifies, 1);
  });

  testWidgets('a still location rebuilds nothing while the clock runs', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(900, 1600));
    await tester.pump();

    final rebuilt = <String>[];
    final printed = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) rebuilt.add(message);
    };
    debugPrintRebuildDirtyWidgets = true;
    for (var frame = 0; frame < 30; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    debugPrintRebuildDirtyWidgets = false;
    debugPrint = printed;

    // Half a second of frames over a location with nothing running. The HUD, the
    // board, and the activity list all hold still, so the frames cost nothing.
    expect(rebuilt, isEmpty, reason: rebuilt.take(10).join('\n'));
  });
}
