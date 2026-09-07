import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'page_header.dart';

/// Parallel Botany / trap timers that do not block the Primary Activity.
///
/// Display and collect only — plant and place start from the location band.
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
                    'Start plant and trap work at the location, like production. '
                    'Collect here when a timer is ready.',
                    style: TextStyle(color: chrome.panelMuted, height: 1.35),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      _TimerSection(
                        title: 'Botany',
                        emptyLabel: 'No botany timers.',
                        timers: timers.where((timer) => timer.kind == 'botany').toList(),
                        db: db,
                        nowMs: nowMs,
                        onCollect: controller.collectTimerAt,
                      ),
                      const SizedBox(height: 8),
                      _TimerSection(
                        title: 'Hunting',
                        emptyLabel: 'No hunting traps.',
                        timers: timers.where((timer) => timer.kind == 'hunting_trap').toList(),
                        db: db,
                        nowMs: nowMs,
                        onCollect: controller.collectTimerAt,
                      ),
                      const SizedBox(height: 8),
                      _TimerSection(
                        title: 'Fishing',
                        emptyLabel: 'No fishing traps.',
                        timers: timers.where((timer) => timer.kind == 'fishing_trap').toList(),
                        db: db,
                        nowMs: nowMs,
                        onCollect: controller.collectTimerAt,
                      ),
                    ],
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

class _TimerSection extends StatelessWidget {
  const _TimerSection({
    required this.title,
    required this.emptyLabel,
    required this.timers,
    required this.db,
    required this.nowMs,
    required this.onCollect,
  });

  final String title;
  final String emptyLabel;
  final List<LocationTimer> timers;
  final GameDatabase db;
  final num nowMs;
  final ValueChanged<String> onCollect;

  @override
  Widget build(BuildContext context) {
    final chrome = UiChrome.of(context);
    return GamePanel(
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: timers.isNotEmpty,
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            title: Text(
              title,
              style: TextStyle(fontWeight: FontWeight.w400, fontSize: 16, color: chrome.panelInk),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                timers.isEmpty ? emptyLabel : '${timers.length} active',
                style: TextStyle(color: chrome.panelMuted, fontSize: 12.5),
              ),
            ),
            children: [
              if (timers.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(emptyLabel, style: TextStyle(color: chrome.panelMuted)),
                )
              else
                for (final timer in timers)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _TimerRow(timer: timer, db: db, nowMs: nowMs, onCollect: onCollect),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimerRow extends StatelessWidget {
  const _TimerRow({
    required this.timer,
    required this.db,
    required this.nowMs,
    required this.onCollect,
  });

  final LocationTimer timer;
  final GameDatabase db;
  final num nowMs;
  final ValueChanged<String> onCollect;

  @override
  Widget build(BuildContext context) {
    final chrome = UiChrome.of(context);
    final location = db.locations.firstWhere(
      (row) => row.raw['Location ID'] == timer.locationId,
      orElse: () => db.locations.first,
    );
    final ready = timerIsReady(timer, nowMs);
    final remainMs = (timerCompletesAtMs(timer) - nowMs).clamp(0, 1 << 62);
    final remainSec = (remainMs / 1000).ceil();
    final title = location.raw['Display Name'] as String? ?? timer.locationId;
    final kindLabel = timer.kind.replaceAll('_', ' ');
    return Material(
      color: chrome.slot,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        title: Text(title, style: TextStyle(color: chrome.panelInk)),
        subtitle: Text(
          ready ? 'Ready · $kindLabel' : '$kindLabel · ${remainSec}s left',
          style: TextStyle(color: chrome.panelMuted),
        ),
        trailing: ready
            ? FilledButton(
                onPressed: () => onCollect(timer.locationId),
                child: const Text('Collect'),
              )
            : null,
      ),
    );
  }
}
