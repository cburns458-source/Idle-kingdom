import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../theme.dart';
import 'format.dart';

/// What the character got up to while the game was closed.
class AwaySummarySheet extends StatelessWidget {
  const AwaySummarySheet({super.key, required this.summary, required this.onDismiss});

  final UnattendedResult summary;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      if (summary.gatheringActions > 0)
        '${formatThousands(summary.gatheringActions)} actions completed',
      if (summary.craftsCompleted > 0) '${formatThousands(summary.craftsCompleted)} items crafted',
      if (summary.combatVictories > 0)
        '${formatThousands(summary.combatVictories)} enemies defeated',
      if (summary.combatDeaths > 0) '${formatThousands(summary.combatDeaths)} defeats',
      if (summary.crittersSpawned > 0)
        '${formatThousands(summary.crittersSpawned)} critters appeared',
    ];
    // A long absence writes a line per craft; the rules merge them per item.
    final messages = consolidateAwayMessages(summary.messages);

    return ColoredBox(
      color: const Color(0xCC120C08),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: GamePanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'While you were away',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                MutedText('${formatDurationMs(summary.effectiveElapsedMs)} of progress'),
                const SizedBox(height: 10),
                // A long absence can list more than the screen holds.
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final line in lines) Text('• $line'),
                        for (final message in messages)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: MutedText(message),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(onPressed: onDismiss, child: const Text('Continue')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
