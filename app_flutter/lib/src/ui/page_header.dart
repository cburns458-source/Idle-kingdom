import 'package:flutter/material.dart';

import '../theme.dart';

/// Title + Close for every pushable page. Close pops one page on the stack.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    required this.onClose,
    this.trailing,
    this.close,
  });

  final String title;
  final VoidCallback onClose;
  final Widget? trailing;

  /// Replaces the compact text Close when a same-size chip is needed.
  final Widget? close;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
            ),
          ),
          if (trailing != null) ...[trailing!, const SizedBox(width: 8)],
          close ??
              GameButton(
                label: 'Close',
                tone: GameButtonTone.secondary,
                compact: true,
                tooltip: 'Close',
                onPressed: onClose,
              ),
        ],
      ),
    );
  }
}
