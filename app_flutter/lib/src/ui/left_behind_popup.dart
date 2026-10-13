import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'game_popup.dart';

/// Copy for loot that rolled but did not fit in the bag.
const String leftBehindPopupMessage = 'Your bag is full. Some loot was left behind.';

/// One overflow row: `Clay x2`.
String leftBehindItemLine(LootGrant grant) =>
    '${grant.displayName} x${jsNumberToString(grant.quantity)}';

/// Lists every stacked overflow grant. Rebuilds if more arrive while open.
Future<void> showLeftBehindLootPopup({
  required BuildContext context,
  required GameController controller,
}) {
  return showGamePopup<void>(
    context: context,
    builder: (dialogContext) {
      return ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return GamePopupCard(
            key: const Key('left-behind-popup'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(leftBehindPopupMessage, style: TextStyle(height: 1.4)),
                if (controller.pendingLeftBehind.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final grant in controller.pendingLeftBehind)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(leftBehindItemLine(grant)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                GameButton(label: 'OK', onPressed: () => Navigator.of(dialogContext).pop()),
              ],
            ),
          );
        },
      );
    },
  );
}
