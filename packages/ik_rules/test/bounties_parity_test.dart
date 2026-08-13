import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  group('bounty catalog parity', () {
    for (final fixture in loadParityFixtures('bounties/catalog')) {
      test(fixture.name, () {
        expect(
          checkParity(fixture, {
            'perHour': bountiesPerHour,
            'bounties': bountyCatalog.map((bounty) => bounty.toJson()).toList(),
          }),
          isNull,
        );
      });
    }
  });

  group('bounty rotation parity', () {
    for (final fixture in loadParityFixtures('bounties/rotation')) {
      test(fixture.name, () {
        final boards = fixture
            .inputField<List<Object?>>('stamps')
            .map((value) => value! as String)
            .map((stamp) {
              final nowMs = jsDateParse(stamp);
              return <String, Object?>{
                'stamp': stamp,
                'hourKey': bountyHourKey(nowMs),
                'board': hourlyBountyBoard(nowMs).toJson(),
              };
            })
            .toList();
        // An hour key the parser rejects falls back to the caller's clock.
        const hourKeys = <String>['2026-08-12T13', '2026-12-31T23', 'not-an-hour'];
        final nowMs = jsDateParse('2026-08-12T21:00:00.000Z');
        expect(
          checkParity(fixture, {
            'boards': boards,
            'expiries': hourKeys
                .map(
                  (hourKey) => <String, Object?>{
                    'hourKey': hourKey,
                    'expires': bountyHourExpiresAtMs(hourKey, nowMs),
                  },
                )
                .toList(),
          }),
          isNull,
        );
      });
    }
  });

  group('bounty progress parity', () {
    for (final fixture in loadParityFixtures('bounties/progress')) {
      if (fixture.name == 'hour-rollover') continue;
      test(fixture.name, () {
        final save = saveOf(fixture);
        final nowMs = fixture.inputField<num>('nowMs');
        final board = hourlyBountyBoard(nowMs);
        final defeated = applyBountyDefeatProgress(save, 'ENM-0001', 3, nowMs);
        final processed = applyBountyProcessProgress(defeated, 'RCP-0001', 2, nowMs);
        final projected = applyBountyProjectProgress(processed, 'PRJ-0007', 1, nowMs);
        expect(
          checkParity(fixture, {
            'synced': syncBountyHour(save, nowMs).toJson(),
            'defeated': defeated.toJson(),
            'processed': processed.toJson(),
            'projected': projected.toJson(),
            'gatherStaysUncounted': applyBountyProcessProgress(
              save,
              'ITEM-0030',
              5,
              nowMs,
            ).toJson(),
            'progressAfter': board.bounties
                .map(
                  (bounty) => <String, Object?>{
                    'id': bounty.id,
                    'kind': bounty.kind,
                    'progress': bountyProgressFor(projected, bounty, nowMs),
                    'ready': isBountyReadyToClaim(projected, bounty, nowMs),
                  },
                )
                .toList(),
          }),
          isNull,
        );
      });
    }

    for (final fixture in loadParityFixtures('bounties/progress')) {
      if (fixture.name != 'hour-rollover') continue;
      test(fixture.name, () {
        final nowMs = fixture.inputField<num>('nowMs');
        final board = hourlyBountyBoard(nowMs);
        // Progress and claims recorded under an hour that has long since passed.
        final stale = saveOf(fixture).copyWith(
          bountyHourKey: '2020-01-01T00',
          bountyProgress: const <String, num>{'BNT-0005': 4},
          bountyClaimedIds: const <String>['BNT-0005'],
        );
        expect(
          checkParity(fixture, {
            'stale': stale.toJson(),
            'synced': syncBountyHour(stale, nowMs).toJson(),
            'readyBefore': board.bounties
                .map((bounty) => isBountyReadyToClaim(stale, bounty, nowMs))
                .toList(),
          }),
          isNull,
        );
      });
    }
  });

  group('bounty board view parity', () {
    for (final fixture in loadParityFixtures('bounties/views')) {
      test(fixture.name, () {
        final nowMs = fixture.inputField<num>('nowMs');
        final board = hourlyBountyBoard(nowMs);
        final save = saveOf(fixture);
        final partial = saveOf(fixture, 'partial');
        final fresh = saveOf(fixture, 'fresh');
        final claims = fixture
            .inputField<List<Object?>>('claims')
            .map((value) => BountyClaimRecord.fromJson(asJsonMap(value)))
            .toList();
        final labels = fixture
            .inputField<List<Object?>>('remainingLabels')
            .map((value) => value! as String)
            .toList();
        List<Object?> rowsJson(List<BountyRowView> rows) =>
            rows.map((row) => row.toJson()).toList();
        expect(
          checkParity(fixture, {
            'rows': rowsJson(bountyRows(save, board, claims, true, nowMs)),
            'signedOutRows': rowsJson(bountyRows(save, board, claims, false, nowMs)),
            'partialRows': rowsJson(bountyRows(partial, board, claims, true, nowMs)),
            'freshRows': rowsJson(
              bountyRows(fresh, board, const <BountyClaimRecord>[], true, nowMs),
            ),
            'rotationLines': labels.map(bountyRotationLine).toList(),
            'claimedNotices': <String>[
              bountyClaimedNotice(180, true),
              bountyClaimedNotice(120, false),
            ],
            'signInNotice': bountySignInNotice,
          }),
          isNull,
        );
      });
    }
  });
}
