import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'page_header.dart';

/// Parallel Botany / trap timers that do not block the Primary Activity.
class TimersView extends StatelessWidget {
  const TimersView({super.key, required this.controller, this.onClose});

  final GameController controller;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final chrome = UiChrome.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final save = controller.save;
        final db = controller.db;
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final timers = save.locationTimers;
        return ColoredBox(
          color: chrome.panel,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (onClose != null)
                  PageHeader(title: 'Timers', onClose: onClose!)
                else
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 12, 12, 8),
                    child: Text(
                      'Timers',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w400),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    'One timer per location. Botany plots and traps run beside your '
                    'Primary Activity.',
                    style: TextStyle(color: chrome.panelMuted, height: 1.35),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: () => controller.plantBestBotanySeedHere(),
                        child: const Text('Plant seed here'),
                      ),
                      FilledButton.tonal(
                        onPressed: () => controller.placeTrapHere(huntingTrapItemId),
                        child: const Text('Place hunting trap'),
                      ),
                      FilledButton.tonal(
                        onPressed: () => controller.placeTrapHere(fishingTrapItemId),
                        child: const Text('Place fishing trap'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: timers.isEmpty
                      ? Center(
                          child: Text(
                            'No active timers.',
                            style: TextStyle(color: chrome.panelMuted),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: timers.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final timer = timers[index];
                            final location = db.locations.firstWhere(
                              (row) => row.raw['Location ID'] == timer.locationId,
                              orElse: () => db.locations.first,
                            );
                            final ready = timerIsReady(timer, nowMs);
                            final remainMs = (timerCompletesAtMs(timer) - nowMs).clamp(0, 1 << 62);
                            final remainSec = (remainMs / 1000).ceil();
                            final title =
                                location.raw['Display Name'] as String? ?? timer.locationId;
                            return Material(
                              color: chrome.slot,
                              borderRadius: BorderRadius.circular(12),
                              child: ListTile(
                                title: Text(title),
                                subtitle: Text(
                                  ready
                                      ? 'Ready · ${timer.kind.replaceAll('_', ' ')}'
                                      : '${timer.kind.replaceAll('_', ' ')} · ${remainSec}s left',
                                ),
                                trailing: ready
                                    ? FilledButton(
                                        onPressed: () =>
                                            controller.collectTimerAt(timer.locationId),
                                        child: const Text('Collect'),
                                      )
                                    : null,
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
