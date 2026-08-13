/// Duration wording, matching `src/ui/formatDuration.ts` so both clients read
/// the same way.
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
