import 'package:flutter/material.dart';

import 'game_popup.dart';

/// One-shot popup for a social action result (join, apply, error, and so on).
///
/// Settles in the top half of the frame. Gold OK, same pair as other card confirms.
Future<void> showSocialAlert(BuildContext context, String message) {
  return showGameAlert(
    context: context,
    message: message,
    confirmLabel: 'OK',
    placement: GamePopupPlacement.topHalf,
  );
}
