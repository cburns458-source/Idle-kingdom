/// Text formatting shared by the panels, worded as the game always has been.
library;

/// Duration wording: `1h 2m 5s`, down to `0s`.
String formatDurationSeconds(num totalSeconds) {
  if (!totalSeconds.isFinite || totalSeconds <= 0) return '0s';
  final whole = totalSeconds.floor();
  final hours = whole ~/ 3600;
  final minutes = (whole % 3600) ~/ 60;
  final seconds = whole % 60;
  if (hours > 0) return '${hours}h ${minutes}m ${seconds}s';
  if (minutes > 0) return '${minutes}m ${seconds}s';
  return '${seconds}s';
}

String formatDurationMs(num milliseconds) => formatDurationSeconds(milliseconds / 1000);

/// Character play time: `3h 12m`, hiding seconds after the first minute.
String formatPlayTimeMs(num milliseconds) {
  if (!milliseconds.isFinite || milliseconds <= 0) return '0m';
  final totalSeconds = (milliseconds / 1000).floor();
  if (totalSeconds < 60) return '${totalSeconds}s';
  final totalMinutes = totalSeconds ~/ 60;
  final days = totalMinutes ~/ (60 * 24);
  final hours = (totalMinutes % (60 * 24)) ~/ 60;
  final minutes = totalMinutes % 60;
  if (days > 0) return hours > 0 ? '${days}d ${hours}h' : '${days}d';
  if (hours > 0) return minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
  return '${minutes}m';
}

/// 12345 -> "12,345", the grouping JavaScript's `toLocaleString()` gives.
String formatThousands(num value) {
  final digits = value.round().abs().toString();
  final grouped = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) grouped.write(',');
    grouped.write(digits[index]);
  }
  return value < 0 ? '-$grouped' : grouped.toString();
}

/// "1 stack" / "2 stacks", so the caller does not spell out the plural each time.
String pluralize(num count, String singular, [String? plural]) {
  return count == 1 ? '1 $singular' : '$count ${plural ?? '${singular}s'}';
}
