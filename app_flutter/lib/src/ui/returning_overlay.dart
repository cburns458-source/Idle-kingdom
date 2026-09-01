import 'package:flutter/material.dart';

import '../session/battery_saver_pref.dart';
import '../theme.dart';

/// Covers the game after a long hide or a cold-boot catch-up.
class ReturningOverlay extends StatelessWidget {
  const ReturningOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final reduceMotion = BatterySaverScope.of(context);
    return ColoredBox(
      color: const Color(0xCC120C08),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!reduceMotion) ...[
                const CircularProgressIndicator(color: Palette.gold),
                const SizedBox(height: 18),
              ],
              const Text(
                'Returning to your adventure…',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w400),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
