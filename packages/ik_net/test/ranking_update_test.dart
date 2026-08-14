import 'package:ik_net/ik_net.dart';
import 'package:test/test.dart';

void main() {
  const noon = 1786568400000; // 2026-08-13T00:00:00.000Z? pinned like other net tests
  final day = DateTime.fromMillisecondsSinceEpoch(noon, isUtc: true);
  final startOfDay = DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch;
  final nextDay = DateTime.utc(day.year, day.month, day.day).add(const Duration(days: 1)).millisecondsSinceEpoch;

  test('names the storage key after the account', () {
    expect(rankingUpdateStorageKey('usr_0001'), 'idle-kingdoms.leaderboard.submit-at:usr_0001');
  });

  test('auto-submits when nothing has been posted, or the UTC day rolled over', () {
    expect(shouldAutoSubmitRanking(null, startOfDay), isTrue);
    expect(shouldAutoSubmitRanking(startOfDay, startOfDay + 60 * 60 * 1000), isFalse);
    expect(shouldAutoSubmitRanking(startOfDay, nextDay), isTrue);
    expect(utcDayKey(startOfDay), utcDayKey(startOfDay + 12 * 60 * 60 * 1000));
    expect(utcDayKey(startOfDay), isNot(utcDayKey(nextDay)));
  });

  test('manual updates wait an hour', () {
    expect(canUpdateRanking(null, startOfDay), isTrue);
    expect(canUpdateRanking(startOfDay, startOfDay + rankingUpdateCooldownMs - 1), isFalse);
    expect(canUpdateRanking(startOfDay, startOfDay + rankingUpdateCooldownMs), isTrue);
    expect(rankingCooldownRemainingMs(startOfDay, startOfDay + 15 * 60 * 1000), 45 * 60 * 1000);
    expect(
      rankingCooldownMessage(45 * 60 * 1000),
      'You can update your ranking again in 45 minutes.',
    );
    expect(rankingCooldownMessage(60 * 1000), 'You can update your ranking again in 1 minute.');
    expect(rankingCooldownMessage(rankingUpdateCooldownMs), 'You can update your ranking again in 1 hour.');
    expect(rankingUpdateHint(startOfDay, startOfDay), 'You can update your ranking again in 1 hour.');
    expect(rankingUpdateHint(null, startOfDay), rankingUpdateReadyHint);
  });

  test('parses a stored timestamp', () {
    expect(parseRankingSubmitAt(null), isNull);
    expect(parseRankingSubmitAt(''), isNull);
    expect(parseRankingSubmitAt('1786568400000'), 1786568400000);
  });
}
