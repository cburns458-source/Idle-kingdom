/// How long a player must wait between manual ranking updates.
const num rankingUpdateCooldownMs = 60 * 60 * 1000;

/// Ignore a second publish that lands in the same couple of seconds as the last.
///
/// Sign-in, session restore, and the first frame of polling can all ask at once.
const num rankingPublishDebounceMs = 3000;

const String rankingUpdateReadyHint = 'Publishes your current totals to the boards.';

const String rankingUpdatedNotice = 'Ranking updated.';

/// The local-storage key that remembers when this account last submitted.
String rankingUpdateStorageKey(String userId) => 'idle-kingdoms.leaderboard.submit-at:$userId';

/// UTC calendar day `YYYY-MM-DD` for [nowMs].
String utcDayKey(num nowMs) {
  final dt = DateTime.fromMillisecondsSinceEpoch(nowMs.round(), isUtc: true);
  final year = dt.year.toString().padLeft(4, '0');
  final month = dt.month.toString().padLeft(2, '0');
  final day = dt.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

num? parseRankingSubmitAt(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return num.tryParse(raw);
}

/// True when this device has not submitted on today's UTC day.
bool shouldAutoSubmitRanking(num? lastSubmitMs, num nowMs) {
  if (lastSubmitMs == null) return true;
  return utcDayKey(lastSubmitMs) != utcDayKey(nowMs);
}

/// True when a manual update is allowed (never submitted, or the hour is up).
bool canUpdateRanking(num? lastSubmitMs, num nowMs) {
  if (lastSubmitMs == null) return true;
  return nowMs - lastSubmitMs >= rankingUpdateCooldownMs;
}

num rankingCooldownRemainingMs(num lastSubmitMs, num nowMs) {
  final left = rankingUpdateCooldownMs - (nowMs - lastSubmitMs);
  return left < 0 ? 0 : left;
}

String rankingCooldownMessage(num remainingMs) {
  final minutes = (remainingMs / 60000).ceil();
  if (minutes <= 1) return 'You can update your ranking again in 1 minute.';
  if (minutes >= 60) return 'You can update your ranking again in 1 hour.';
  return 'You can update your ranking again in $minutes minutes.';
}

String rankingUpdateHint(num? lastSubmitMs, num nowMs) {
  if (lastSubmitMs != null && !canUpdateRanking(lastSubmitMs, nowMs)) {
    return rankingCooldownMessage(rankingCooldownRemainingMs(lastSubmitMs, nowMs));
  }
  return rankingUpdateReadyHint;
}

/// UTC hour mark `YYYY-MM-DDTHH` for [nowMs].
String utcHourKey(num nowMs) {
  final dt = DateTime.fromMillisecondsSinceEpoch(nowMs.round(), isUtc: true);
  final year = dt.year.toString().padLeft(4, '0');
  final month = dt.month.toString().padLeft(2, '0');
  final day = dt.day.toString().padLeft(2, '0');
  final hour = dt.hour.toString().padLeft(2, '0');
  return '$year-$month-${day}T$hour';
}

/// Milliseconds until the next UTC :00 after [nowMs].
num msUntilNextUtcHour(num nowMs) {
  final dt = DateTime.fromMillisecondsSinceEpoch(nowMs.round(), isUtc: true);
  final next = DateTime.utc(dt.year, dt.month, dt.day, dt.hour).add(const Duration(hours: 1));
  return next.millisecondsSinceEpoch - nowMs;
}

/// True when [nowMs] is in a later UTC hour than [lastPublishMs].
bool shouldPublishForUtcHour(num? lastPublishMs, num nowMs) {
  if (lastPublishMs == null) return true;
  return utcHourKey(lastPublishMs) != utcHourKey(nowMs);
}

/// True when opening the app should publish again, skipping an immediate double-fire.
bool shouldPublishOnOpen(num? lastPublishMs, num nowMs) {
  if (lastPublishMs == null) return true;
  return nowMs - lastPublishMs >= rankingPublishDebounceMs;
}
