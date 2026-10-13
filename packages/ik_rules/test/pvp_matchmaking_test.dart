import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = filterLaunchContent(assertGameDatabaseShape(contentDatabaseJson()));
  });

  test('the sixth ranked win is unpaid and the cap resets at midnight UTC', () {
    final beforeMidnight = DateTime.utc(2026, 8, 13, 23, 59, 59).millisecondsSinceEpoch;
    final midnight = DateTime.utc(2026, 8, 14).millisecondsSinceEpoch;
    expect(rankedPvpDayKey(beforeMidnight), '2026-08-13');
    expect(rankedPvpDayKey(midnight), '2026-08-14');

    var save = createNewSave(db, beforeMidnight);
    for (var i = 0; i < rankedPvpDailyCap; i++) {
      save = applyRankedPvpResult(save, true, beforeMidnight).save;
    }
    expect(rankedWinsRemaining(save, beforeMidnight), 0);

    final sixth = applyRankedPvpResult(save, true, beforeMidnight);
    expect(sixth.paid, isFalse);
    expect(sixth.code, rankedPvpDailyCapCode);
    expect(sixth.winsRemaining, 0);
    expect(sixth.save.gold, save.gold);
    expect(sixth.save.rankedPvpFightsToday, rankedPvpDailyCap + 1);

    expect(rankedWinsRemaining(sixth.save, midnight), rankedPvpDailyCap);
    final afterMidnight = applyRankedPvpResult(sixth.save, true, midnight);
    expect(afterMidnight.paid, isTrue);
    expect(afterMidnight.code, isNull);
    expect(afterMidnight.winsRemaining, rankedPvpDailyCap - 1);
    expect(afterMidnight.save.gold, sixth.save.gold);
    expect(afterMidnight.pointsGained, 25);
    expect(afterMidnight.save.plazaPoints, sixth.save.plazaPoints + 25);
    expect(afterMidnight.save.rankedPvpFightsToday, 1);
    expect(afterMidnight.save.rankedPvpDayKey, '2026-08-14');
  });
}
