import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/action_stage.dart';
import 'package:idle_kingdoms/src/ui/mass_roster.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

MassParticipantView _player({
  required String id,
  required String name,
  num damage = 0,
  bool late = false,
  bool lockedIn = true,
  bool present = true,
}) {
  return MassParticipantView(
    userId: id,
    username: name,
    late: late,
    lockedIn: lockedIn,
    present: present,
    damageDealt: damage,
  );
}

MassEncounterSnapshot _snap({
  String status = 'lobby',
  String? countdownEndsAt,
  num lockedCount = 0,
  List<MassParticipantView> participants = const <MassParticipantView>[],
  MassYouView? you,
}) {
  return MassEncounterSnapshot(
    encounterId: 'enc-1',
    enemyId: dragonEnemyId,
    status: status,
    countdownEndsAt: countdownEndsAt,
    lockedCount: lockedCount,
    soloHp: 1000,
    healthMultiplier: 1,
    totalHp: 1000,
    remainingHp: 800,
    dropScale: 1,
    minDamage: 30,
    participants: participants,
    you: you,
  );
}

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  test('counts present lobby players and locked-in fighters, capped at 100', () {
    final lobby = _snap(
      participants: [
        _player(id: 'a', name: 'Ash', present: true, lockedIn: false),
        _player(id: 'b', name: 'Bea', present: false, lockedIn: false),
      ],
    );
    expect(massRosterCount(lobby), 1);
    expect(massRosterRows(lobby).single.username, 'Ash');

    final fight = _snap(
      status: 'fighting',
      lockedCount: 2,
      participants: [
        _player(id: 'a', name: 'Ash', damage: 40, present: false, lockedIn: true),
        _player(id: 'b', name: 'Bea', damage: 10, present: true, lockedIn: true),
        _player(id: 'c', name: 'Cy', damage: 99, present: true, lockedIn: false, late: true),
      ],
    );
    expect(massRosterCount(fight), 2);
    expect(massRosterRows(fight).map((row) => row.username).toList(), ['Ash', 'Bea']);
  });

  test('damage shares ignore late joiners and sum to 100 when there is damage', () {
    final rows = [
      _player(id: 'a', name: 'Ash', damage: 75, lockedIn: true),
      _player(id: 'b', name: 'Bea', damage: 25, lockedIn: true),
      _player(id: 'c', name: 'Cy', damage: 50, late: true, lockedIn: false),
    ];
    expect(massDamageSharePercent(rows[0], rows), 75);
    expect(massDamageSharePercent(rows[1], rows), 25);
    expect(massDamageSharePercent(rows[2], rows), 0);
  });

  test('countdown never goes below zero', () {
    final now = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch;
    final mass = _snap(
      countdownEndsAt: DateTime.fromMillisecondsSinceEpoch(
        now - 5000,
        isUtc: true,
      ).toIso8601String(),
    );
    expect(massCountdownRemainingSeconds(mass, now), 0);
  });

  testWidgets('lobby shows countdown, cap, and names without helper copy', (tester) async {
    final now = DateTime.utc(2026, 1, 1, 0, 0, 10).millisecondsSinceEpoch;
    final ends = DateTime.utc(2026, 1, 1, 0, 1, 10).toIso8601String();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: MassRoster(
            mass: _snap(
              countdownEndsAt: ends,
              participants: [_player(id: 'a', name: 'Ash', lockedIn: false)],
            ),
            nowMs: now,
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('mass-countdown')), findsOne);
    expect(find.text('60s'), findsOne);
    expect(find.text('1/100'), findsOne);
    expect(find.text('Ash'), findsOne);
    expect(find.textContaining('Waiting'), findsNothing);
    expect(find.textContaining('first in line'), findsNothing);
  });

  testWidgets('empty lobby shows 0/100 and no leftover names', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: MassRoster(mass: _snap(), nowMs: 0)),
      ),
    );
    expect(find.text('0/100'), findsOne);
    expect(find.byKey(const Key('mass-participants')), findsNothing);
  });

  testWidgets('late joiner is spectating with no drops, and shares are listed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: MassRoster(
            mass: _snap(
              status: 'fighting',
              lockedCount: 2,
              participants: [
                _player(id: 'a', name: 'Ash', damage: 80),
                _player(id: 'b', name: 'Bea', damage: 20),
                _player(id: 'c', name: 'Cy', damage: 0, late: true, lockedIn: false),
              ],
              you: const MassYouView(
                late: true,
                lockedIn: false,
                present: true,
                damageDealt: 0,
                payoutClaimed: false,
              ),
            ),
            nowMs: 0,
          ),
        ),
      ),
    );
    expect(find.text('2/100'), findsOne);
    expect(find.byKey(const Key('mass-spectating')), findsOne);
    expect(find.text('Spectating · no drops'), findsOne);
    expect(find.text('Ash'), findsOne);
    expect(find.text('80%'), findsOne);
    expect(find.text('Bea'), findsOne);
    expect(find.text('20%'), findsOne);
    expect(find.byKey(const Key('mass-countdown')), findsNothing);
  });

  testWidgets('closed encounters hide the roster', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: MassRoster(mass: _snap(status: 'closed'), nowMs: 0),
        ),
      ),
    );
    expect(find.byKey(const Key('mass-player-count')), findsNothing);
  });

  testWidgets('ActionStage lobby ticks the countdown from the mass snapshot', (tester) async {
    final clock = TestClock(startMs: DateTime.utc(2026, 1, 1).millisecondsSinceEpoch);
    final controller = buildController(
      database,
      clock: clock,
      seed: startedCharacter(database).copyWith(
        currentLocationId: dragonLocationId,
        currentActivityId: dragonActivityId,
        massEncounterId: 'enc-1',
      ),
    );
    addTearDown(controller.dispose);
    controller.acceptMassSnapshot(
      _snap(
        countdownEndsAt: DateTime.utc(2026, 1, 1, 0, 1).toIso8601String(),
        participants: [_player(id: 'a', name: 'Ash', lockedIn: false)],
      ),
    );
    await pumpPanel(tester, ActionStage(controller: controller));
    expect(find.text('60s'), findsOne);
    expect(find.text('1/100'), findsOne);
    expect(find.text('Ash'), findsOne);
  });
}
