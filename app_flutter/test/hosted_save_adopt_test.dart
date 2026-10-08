import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/hosted_save_adopt.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  test('start_activity keeps the local action clock when the activity matches', () {
    final local = startedCharacter(database).copyWith(
      currentActivityId: 'ACT-0021',
      activityStartedAt: isoFromMs(testStartMs),
      currentActionId: 'ACN-0035',
      actionStartedAt: isoFromMs(testStartMs),
      actionDurationMs: 12000,
    );
    final incoming = local.copyWith(
      gold: local.gold + 10,
      activityStartedAt: isoFromMs(testStartMs + 1000),
      actionStartedAt: isoFromMs(testStartMs + 1000),
      currentActionId: 'ACN-9999',
      actionDurationMs: 8000,
    );

    final merged = mergeHostedStartSave(local, incoming, command: 'start_activity');

    expect(merged.gold, local.gold + 10);
    expect(merged.activityStartedAt, local.activityStartedAt);
    expect(merged.currentActionId, 'ACN-0035');
    expect(merged.actionStartedAt, local.actionStartedAt);
    expect(merged.actionDurationMs, 12000);
  });

  test('start_activity keeps the local combat round clock', () {
    final local = startedCharacter(database).copyWith(
      currentActivityId: 'ACT-0002',
      activityStartedAt: isoFromMs(testStartMs),
      currentActionId: 'ACN-0100',
      actionStartedAt: isoFromMs(testStartMs),
      combatEnemyId: 'ENM-0001',
      combatEnemyHp: 40,
      combatRoundStartedAt: isoFromMs(testStartMs),
      combatEatUntil: isoFromMs(testStartMs + 1000),
    );
    final incoming = local.copyWith(
      combatRoundStartedAt: isoFromMs(testStartMs + 1000),
      combatEatUntil: isoFromMs(testStartMs + 2000),
      combatEnemyHp: 40,
    );

    final merged = mergeHostedStartSave(local, incoming, command: 'start_activity');

    expect(merged.combatRoundStartedAt, local.combatRoundStartedAt);
    expect(merged.combatEatUntil, local.combatEatUntil);
    expect(merged.combatEnemyId, 'ENM-0001');
  });

  test('travel keeps local HP unless a new fight started', () {
    final local = startedCharacter(database).copyWith(
      currentLocationId: 'LOC-0001',
      currentHp: 190,
      lastDamagedAt: isoFromMs(testStartMs),
      hpRegenStreak: 2,
    );
    final incoming = local.copyWith(
      currentLocationId: 'LOC-0009',
      currentHp: 150,
      lastDamagedAt: isoFromMs(testStartMs - 10_000),
      hpRegenStreak: 0,
    );

    final merged = mergeHostedStartSave(local, incoming, command: 'travel');
    expect(merged.currentLocationId, 'LOC-0009');
    expect(merged.currentHp, 190);
    expect(merged.lastDamagedAt, local.lastDamagedAt);
    expect(merged.hpRegenStreak, 2);
  });

  test('travel keeps local action clocks when destination and activity match', () {
    final local = startedCharacter(database).copyWith(
      currentLocationId: 'LOC-0009',
      currentActivityId: 'ACT-0021',
      activityStartedAt: isoFromMs(testStartMs),
      currentActionId: 'ACN-0035',
      actionStartedAt: isoFromMs(testStartMs),
      actionDurationMs: 12000,
      combatRoundStartedAt: isoFromMs(testStartMs),
    );
    final incoming = local.copyWith(
      gold: local.gold + 4,
      activityStartedAt: isoFromMs(testStartMs + 1000),
      actionStartedAt: isoFromMs(testStartMs + 1000),
      currentActionId: 'ACN-9999',
      actionDurationMs: 8000,
      combatRoundStartedAt: isoFromMs(testStartMs + 1000),
    );

    final merged = mergeHostedStartSave(local, incoming, command: 'travel');

    expect(merged.gold, local.gold + 4);
    expect(merged.currentLocationId, 'LOC-0009');
    expect(merged.currentActivityId, 'ACT-0021');
    expect(merged.activityStartedAt, local.activityStartedAt);
    expect(merged.currentActionId, 'ACN-0035');
    expect(merged.actionStartedAt, local.actionStartedAt);
    expect(merged.actionDurationMs, 12000);
    expect(merged.combatRoundStartedAt, local.combatRoundStartedAt);
  });

  test('travel takes server clocks when the destination or activity differs', () {
    final local = startedCharacter(database).copyWith(
      currentLocationId: 'LOC-0009',
      currentActivityId: 'ACT-0021',
      actionStartedAt: isoFromMs(testStartMs),
      currentActionId: 'ACN-0035',
    );
    final otherTile = local.copyWith(
      currentLocationId: 'LOC-0001',
      actionStartedAt: isoFromMs(testStartMs + 1000),
    );
    final otherActivity = local.copyWith(
      currentActivityId: 'ACT-0012',
      actionStartedAt: isoFromMs(testStartMs + 1000),
      currentActionId: 'ACN-0001',
    );

    expect(
      mergeHostedStartSave(local, otherTile, command: 'travel').actionStartedAt,
      otherTile.actionStartedAt,
    );
    expect(
      mergeHostedStartSave(local, otherActivity, command: 'travel').currentActionId,
      'ACN-0001',
    );
  });

  test('travel into a new fight takes the server HP', () {
    final local = startedCharacter(database).copyWith(currentHp: 190, combatEnemyId: null);
    final incoming = local.copyWith(
      currentLocationId: 'LOC-0003',
      currentHp: 150,
      combatEnemyId: 'ENM-0001',
      combatEnemyHp: 40,
    );

    final merged = mergeHostedStartSave(local, incoming, command: 'travel');
    expect(merged.currentHp, 150);
    expect(merged.combatEnemyId, 'ENM-0001');
  });

  test('sell and conflict pulls take the server clocks', () {
    final local = startedCharacter(database).copyWith(
      currentActivityId: 'ACT-0021',
      actionStartedAt: isoFromMs(testStartMs),
      currentActionId: 'ACN-0035',
      actionDurationMs: 12000,
    );
    final incoming = local.copyWith(
      currentActivityId: null,
      currentActionId: null,
      actionStartedAt: null,
      actionDurationMs: null,
    );

    expect(mergeHostedStartSave(local, incoming).actionStartedAt, isNull);
    expect(
      mergeHostedStartSave(local, incoming, command: 'sell_inventory').actionStartedAt,
      isNull,
    );
  });

  test('set_loadout keeps the running bar and the HP the player already sees', () {
    final local = startedCharacter(database).copyWith(
      currentActivityId: 'ACT-0021',
      activityStartedAt: isoFromMs(testStartMs),
      currentActionId: 'ACN-0035',
      actionStartedAt: isoFromMs(testStartMs),
      actionDurationMs: 12000,
      currentHp: 190,
    );
    final incoming = local.copyWith(
      gold: local.gold + 1,
      actionStartedAt: isoFromMs(testStartMs + 1000),
      currentActionId: 'ACN-0001',
      actionDurationMs: 8000,
      currentHp: 140,
      maxHp: 200,
    );

    final merged = mergeHostedStartSave(local, incoming, command: 'set_loadout');
    expect(merged.gold, local.gold + 1);
    expect(merged.actionStartedAt, local.actionStartedAt);
    expect(merged.currentActionId, 'ACN-0035');
    expect(merged.currentHp, 190);
    expect(merged.maxHp, 200);
  });

  test('set_loadout into a new fight takes the server HP', () {
    final local = startedCharacter(database).copyWith(currentHp: 190);
    final incoming = local.copyWith(currentHp: 80, combatEnemyId: 'ENM-0001', combatEnemyHp: 20);
    final merged = mergeHostedStartSave(local, incoming, command: 'set_loadout');
    expect(merged.currentHp, 80);
    expect(merged.combatEnemyId, 'ENM-0001');
  });

  test('a different activity adopts the server start whole', () {
    final local = startedCharacter(database).copyWith(
      currentActivityId: 'ACT-0021',
      actionStartedAt: isoFromMs(testStartMs),
      currentActionId: 'ACN-0035',
      actionDurationMs: 12000,
    );
    final incoming = local.copyWith(
      currentActivityId: 'ACT-0012',
      actionStartedAt: isoFromMs(testStartMs + 1000),
      currentActionId: 'ACN-0001',
    );

    final merged = mergeHostedStartSave(local, incoming, command: 'start_activity');
    expect(merged.currentActivityId, 'ACT-0012');
    expect(merged.actionStartedAt, incoming.actionStartedAt);
    expect(merged.currentActionId, 'ACN-0001');
  });

  test('adopting a late start_activity does not rewind the first gathering bar', () {
    final clock = TestClock();
    final controller = buildController(database, seed: startedCharacter(database), clock: clock);
    addTearDown(controller.dispose);

    controller.startActivity('ACT-0021');
    expect(controller.save.currentActionId, isNotNull);
    final localStartedAt = controller.save.actionStartedAt;

    clock.advance(1000);
    controller.tick();
    final progressBefore = actionProgressAt(controller.save, clock.read());
    expect(progressBefore, greaterThan(0));

    final lateStart = controller.save.copyWith(
      actionStartedAt: isoFromMs(testStartMs + 1000),
      activityStartedAt: isoFromMs(testStartMs + 1000),
    );
    controller.adoptHostedSave(lateStart, command: 'start_activity');

    expect(controller.save.actionStartedAt, localStartedAt);
    expect(actionProgressAt(controller.save, clock.read()), progressBefore);
  });

  test('a conflict pull does not rewind a local arrival', () {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
    );
    addTearDown(controller.dispose);
    controller.setMapTravelAnimation(false);
    expect(controller.travelTo('LOC-0001', mainMapId), isTrue);
    expect(controller.save.currentLocationId, 'LOC-0001');

    final stale = controller.save.copyWith(currentLocationId: 'LOC-0009');
    controller.adoptHostedSave(stale);

    expect(controller.save.currentLocationId, 'LOC-0001');
    expect(wouldRewindCurrentLocation(controller.save, stale), isTrue);
  });

  test('startActivity and travel keep the reward strip', () {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
    );
    addTearDown(controller.dispose);
    controller.setMapTravelAnimation(false);
    controller.noteReward(
      const ActionRewardBundle(
        id: 'kept',
        xpRewards: [],
        loot: [LootGrant(itemId: 'ITEM-0025', quantity: 1, displayName: 'Potato')],
        goldGained: 0,
      ),
    );
    expect(controller.recentRewards.single.id, 'kept');

    controller.startActivity('ACT-0021');
    expect(controller.recentRewards.single.id, 'kept');

    expect(controller.travelTo('LOC-0001', mainMapId), isTrue);
    expect(controller.recentRewards.single.id, 'kept');
  });

  test('activity and travel stay put until the hosted switch returns', () async {
    final clock = TestClock();
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0001'),
      clock: clock,
    );
    addTearDown(controller.dispose);
    final gates = <Completer<String?>>[];
    controller.submitGameCommand = (command, [args = const <String, Object?>{}]) {
      final gate = Completer<String?>();
      gates.add(gate);
      return gate.future;
    };

    controller.startActivity('ACT-0021');
    expect(controller.switchBusy, isTrue);
    expect(controller.save.currentActivityId, 'ACT-0021');
    final startedAt = controller.save.actionStartedAt;
    expect(gates, hasLength(1));

    clock.advance(500);
    controller.startActivity('ACT-0001');
    controller.stopActivity();
    expect(controller.travelTo('LOC-0009', mainMapId), isFalse);
    expect(controller.save.currentActivityId, 'ACT-0021');
    expect(controller.save.actionStartedAt, startedAt);
    expect(controller.save.currentLocationId, 'LOC-0001');
    expect(gates, hasLength(1));

    gates.single.complete();
    await pumpEventQueue();
    expect(controller.switchBusy, isFalse);

    expect(controller.travelTo('LOC-0009', mainMapId), isTrue);
    expect(controller.save.currentLocationId, 'LOC-0009');
    expect(controller.switchBusy, isTrue);
  });

  test('a signed-in start waits for the server, and a refusal changes nothing', () async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0001'),
    );
    addTearDown(controller.dispose);
    controller.hostedPlay = () => true;
    final gate = Completer<String?>();
    controller.submitGameCommand = (command, [args = const <String, Object?>{}]) => gate.future;

    controller.startActivity('ACT-0021');
    expect(controller.switchBusy, isTrue);
    expect(controller.pendingSwitch, 'start_activity');
    expect(controller.save.currentActivityId, isNot('ACT-0021'));

    gate.complete('You cannot start that.');
    await pumpEventQueue();
    expect(controller.switchBusy, isFalse);
    expect(controller.switchSpinner, isFalse);
    expect(controller.save.currentActivityId, isNot('ACT-0021'));
    expect(controller.activityError, 'You cannot start that.');
  });

  testWidgets('the loading circle waits out a fast answer', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0001'),
    );
    addTearDown(controller.dispose);
    controller.hostedPlay = () => true;
    final gate = Completer<String?>();
    controller.submitGameCommand = (command, [args = const <String, Object?>{}]) => gate.future;

    controller.startActivity('ACT-0021');
    expect(controller.switchSpinner, isFalse);
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.switchSpinner, isTrue);

    final started = requestActivityStart(
      controller.db,
      controller.save,
      'ACT-0021',
      controller.session.clock(),
      () => 0,
    );
    expect(started.ok, isTrue, reason: started.reason);
    gate.complete(null);
    // The adopt stands in for the server copy arriving with the command.
    controller.adoptHostedSave(started.save!, command: 'start_activity');
    await tester.pump();
    expect(controller.save.currentActivityId, 'ACT-0021');
    expect(controller.switchBusy, isFalse);
  });

  test('signed-in travel arrives when the server answers, and a walk can hold it', () async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0001'),
    );
    addTearDown(controller.dispose);
    controller.hostedPlay = () => true;
    final gate = Completer<String?>();
    controller.submitGameCommand = (command, [args = const <String, Object?>{}]) async {
      await gate.future;
      final plan = planTravel(
        controller.db,
        controller.save,
        'LOC-0009',
        mainMapId,
        controller.session.clock(),
        () => 0,
      );
      final arrival = (plan as TravelInstant).arrival;
      controller.adoptHostedSave(arrival.save, command: 'travel');
      return null;
    };

    var arrived = false;
    controller.deferArrival();
    expect(controller.travelTo('LOC-0009', mainMapId, onArrived: () => arrived = true), isTrue);
    expect(controller.save.currentLocationId, 'LOC-0001');

    gate.complete(null);
    await pumpEventQueue();
    expect(controller.save.currentLocationId, 'LOC-0001', reason: 'the walk is still going');
    expect(arrived, isFalse);
    expect(controller.switchBusy, isTrue);

    controller.releaseArrival();
    expect(controller.save.currentLocationId, 'LOC-0009');
    expect(arrived, isTrue);
    expect(controller.switchBusy, isFalse);
  });
}
