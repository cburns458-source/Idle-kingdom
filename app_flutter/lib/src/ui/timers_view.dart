import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'page_header.dart';

/// Parallel Botany / trap timers that do not block the Primary Activity.
///
/// Display and collect only — plant and place start from the location band.
class TimersView extends StatefulWidget {
  const TimersView({super.key, required this.controller, this.onClose});

  final GameController controller;
  final VoidCallback? onClose;

  @override
  State<TimersView> createState() => _TimersViewState();
}

class _TimersViewState extends State<TimersView> {
  Timer? _ticker;

  GameController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chrome = UiChrome.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final save = controller.save;
        final db = controller.db;
        final nowMs = controller.session.clock();
        final timers = save.locationTimers;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.onClose != null)
              PageHeader(title: 'Timers', onClose: widget.onClose!)
            else
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Text('Timers', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w400)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(
                'Start plant and trap work at the location, like production. '
                'Collect here when a timer is ready.',
                style: TextStyle(color: chrome.embossFace, height: 1.35, fontSize: 12.5),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                children: [
                  _TimerSection(
                    title: 'Botany',
                    emptyLabel: 'No botany timers.',
                    timers: timers.where((timer) => timer.kind == 'botany').toList(),
                    db: db,
                    nowMs: nowMs,
                    onCollect: controller.collectTimerAt,
                  ),
                  const SizedBox(height: 12),
                  _TimerSection(
                    title: 'Hunting',
                    emptyLabel: 'No hunting traps.',
                    timers: timers.where((timer) => timer.kind == 'hunting_trap').toList(),
                    db: db,
                    nowMs: nowMs,
                    onCollect: controller.collectTimerAt,
                  ),
                  const SizedBox(height: 12),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 16)),
        const SizedBox(height: 4),
        Text(
          timers.isEmpty ? emptyLabel : '${timers.length} active',
          style: TextStyle(color: chrome.embossFace, fontSize: 12.5),
        ),
        if (timers.isEmpty)
          const SizedBox(height: 4)
        else
          for (final timer in timers)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _TimerRow(timer: timer, db: db, nowMs: nowMs, onCollect: onCollect),
            ),
      ],
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
    final remainMs = (timerCompletesAtMs(timer) - nowMs).clamp(0, timer.durationMs);
    final title = location.raw['Display Name'] as String? ?? timer.locationId;
    final kindLabel = timer.kind.replaceAll('_', ' ');
    final remainLabel = formatDurationMs(remainMs);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14)),
              Text(
                ready ? 'Ready · $kindLabel' : '$kindLabel · $remainLabel left',
                style: TextStyle(color: chrome.embossFace, fontSize: 12.5),
              ),
            ],
          ),
        ),
        if (ready)
          GameButton(label: 'Collect', compact: true, onPressed: () => onCollect(timer.locationId)),
      ],
    );
  }
}
