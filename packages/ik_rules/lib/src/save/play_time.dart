import 'dart:math' as math;

import 'generated/save_models.dart';

/// Add elapsed character time. Negative, zero, and non-finite spans are ignored
/// so a clock jump backward cannot rewind the total.
PlayerSave accruePlayTime(PlayerSave save, num elapsedMs) {
  if (!elapsedMs.isFinite || elapsedMs <= 0) return save;
  return save.copyWith(playTimeMs: save.playTimeMs + elapsedMs);
}

/// How much of a live-session gap to credit. Short frames accrue in full;
/// longer gaps (background, a paused ticker) credit up to the unattended cap so
/// away time matches catch-up instead of dumping uncapped wall-clock hours.
num livePlayCreditMs(num elapsedMs, num awayCapMs) {
  if (!elapsedMs.isFinite || elapsedMs <= 0) return 0;
  final cap = awayCapMs.isFinite && awayCapMs > 0 ? awayCapMs : 0;
  return math.min(elapsedMs, cap);
}

PlayerSave creditElapsedPlayTime(PlayerSave save, num elapsedMs, num awayCapMs) {
  return accruePlayTime(save, livePlayCreditMs(elapsedMs, awayCapMs));
}
