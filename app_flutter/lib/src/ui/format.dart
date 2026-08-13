/// Text formatting shared by the panels. Wording follows the React client so the
/// two read identically.
library;

/// Duration wording, matching `src/ui/formatDuration.ts`.
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
