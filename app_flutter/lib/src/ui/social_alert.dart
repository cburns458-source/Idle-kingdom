import 'package:flutter/material.dart';

import '../theme.dart';

/// One-shot popup for a social action result (join, apply, error, and so on).
///
/// Replaces the old sticky [SocialNotice] banner that every social panel
/// painted from the shared multiplayer notice string.
Future<void> showSocialAlert(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Palette.parchmentDeep,
      content: Text(message),
      actions: [
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
      ],
    ),
  );
}
