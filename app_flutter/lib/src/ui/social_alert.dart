import 'package:flutter/material.dart';

import '../theme.dart';
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

/// The same card as [showSocialAlert], painted in the shell stack so a covering
/// page such as Guilds cannot sit on top of it.
class SocialAlertOverlay extends StatelessWidget {
  const SocialAlertOverlay({super.key, required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xCC120C08)),
        SafeArea(
          child: Align(
            alignment: const Alignment(0, -0.65),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 400,
                  maxHeight: MediaQuery.sizeOf(context).height * 0.48,
                ),
                child: GamePopupCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(message, style: const TextStyle(height: 1.4)),
                      const SizedBox(height: 14),
                      GameButton(label: 'OK', onPressed: onClose),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
