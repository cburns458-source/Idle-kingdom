import 'package:flutter/material.dart';

import '../theme.dart';

/// A gold progress circle. Flutter draws it, so no extra art is needed.
class GameWaitMark extends StatelessWidget {
  const GameWaitMark({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CircularProgressIndicator(strokeWidth: 2, color: Palette.gold),
    );
  }
}

/// Dims the screen and shows [GameWaitMark] until a slow action answers.
class GameWaitVeil extends StatelessWidget {
  const GameWaitVeil({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      child: ColoredBox(
        color: const Color(0x99120C08),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const GameWaitMark(size: 36),
              if (label != null) ...[
                const SizedBox(height: 10),
                Text(
                  label!,
                  style: const TextStyle(color: Palette.gold, fontSize: GameFont.m),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
