import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  test('replaces inflated gold, a claimed bounty, and raised PvP counters', () {
    final db = assertGameDatabaseShape(contentDatabaseJson());
    final nowMs = jsDateParse('2026-08-13T18:00:00.000Z');
    final server = createNewSave(db, nowMs).copyWith(
      gold: 40,
      bountyClaimedIds: const <String>[],
      rankedPvpWins: 1,
      rankedPvpLosses: 0,
      rankedPvpDayKey: '2026-08-13',
      rankedPvpFightsToday: 1,
    );
    final client = server.copyWith(
      gold: 40000,
      bountyClaimedIds: const <String>['BNT-0001'],
      rankedPvpWins: 9,
      rankedPvpLosses: 3,
      rankedPvpFightsToday: 5,
      motto: 'honest other progress',
    );
    expect(clientSaveRaisesPayouts(server, client), isTrue);
    final next = replaceUnauthorizedPayouts(server, client);
    expect(next.gold, 40);
    expect(next.bountyClaimedIds, isEmpty);
    expect(next.rankedPvpWins, 1);
    expect(next.rankedPvpLosses, 0);
    expect(next.rankedPvpFightsToday, 1);
    expect(next.motto, 'honest other progress');
  });
}
