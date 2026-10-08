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
}
