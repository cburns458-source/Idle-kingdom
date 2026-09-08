import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'page_header.dart';

/// Parallel Botany / trap spots that do not block the Primary Activity.
///
/// Lists discovered spots (even empty). Timers start at the location; travel
/// here to collect when ready.
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

  List<_DiscoveredSpot> _spotsForKind(PlayerSave save, String kind) {
    final spots = <_DiscoveredSpot>[];
    for (final key in save.discoveredTimerSpotIds) {
      final parsed = parseTimerSpotKey(key);
      if (parsed == null || parsed.kind != kind) continue;
      final active = timerAtLocationKind(save, parsed.locationId, kind);
      spots.add(
        _DiscoveredSpot(
          kind: parsed.kind,
          locationId: parsed.locationId,
          timer: active,
        ),
      );
    }
    spots.sort((a, b) => a.locationId.compareTo(b.locationId));
    return spots;
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
                'Timers start at locations. Travel here to collect when ready.',
                style: TextStyle(color: chrome.embossFace, height: 1.35, fontSize: 12.5),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                children: [
                  _TimerSection(
                    title: 'Botany',
                    emptyLabel: 'No botany spots discovered yet.',
                    spots: _spotsForKind(save, 'botany'),
                    db: db,
                    nowMs: nowMs,
                    onTravel: (locationId, mapId) => controller.travelTo(locationId, mapId),
                  ),
                  const SizedBox(height: 12),
                  _TimerSection(
                    title: 'Hunting',
                    emptyLabel: 'No hunting traps discovered yet.',
                    spots: _spotsForKind(save, 'hunting_trap'),
                    db: db,
                    nowMs: nowMs,
                    onTravel: (locationId, mapId) => controller.travelTo(locationId, mapId),
                  ),
                  const SizedBox(height: 12),
                  _TimerSection(
                    title: 'Fishing',
                    emptyLabel: 'No fishing traps discovered yet.',
                    spots: _spotsForKind(save, 'fishing_trap'),
                    db: db,
                    nowMs: nowMs,
                    onTravel: (locationId, mapId) => controller.travelTo(locationId, mapId),
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

class _DiscoveredSpot {
  const _DiscoveredSpot({required this.kind, required this.locationId, required this.timer});

  final String kind;
  final String locationId;
  final LocationTimer? timer;
}

class _TimerSection extends StatelessWidget {
  const _TimerSection({
    required this.title,
    required this.emptyLabel,
    required this.spots,
    required this.db,
    required this.nowMs,
    required this.onTravel,
  });

  final String title;
  final String emptyLabel;
  final List<_DiscoveredSpot> spots;
  final GameDatabase db;
  final num nowMs;
  final void Function(String locationId, String mapId) onTravel;

  @override
  Widget build(BuildContext context) {
    final chrome = UiChrome.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 16)),
        const SizedBox(height: 4),
        Text(
          spots.isEmpty ? emptyLabel : '${spots.length} spot${spots.length == 1 ? '' : 's'}',
          style: TextStyle(color: chrome.embossFace, fontSize: 12.5),
        ),
        if (spots.isEmpty)
          const SizedBox(height: 4)
        else
          for (final spot in spots)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _TimerRow(spot: spot, db: db, nowMs: nowMs, onTravel: onTravel),
            ),
      ],
    );
  }
}

class _TimerRow extends StatelessWidget {
  const _TimerRow({
    required this.spot,
    required this.db,
    required this.nowMs,
    required this.onTravel,
  });

  final _DiscoveredSpot spot;
  final GameDatabase db;
  final num nowMs;
  final void Function(String locationId, String mapId) onTravel;

  @override
  Widget build(BuildContext context) {
    final chrome = UiChrome.of(context);
    final location = db.locations.firstWhere(
      (row) => row.raw['Location ID'] == spot.locationId,
      orElse: () => db.locations.first,
    );
    final mapId = getLocationMapId(location);
    final title = location.raw['Display Name'] as String? ?? spot.locationId;
    final timer = spot.timer;
    final String status;
    if (timer == null) {
      status = 'Empty';
    } else if (timerIsReady(timer, nowMs)) {
      status = 'Ready';
    } else {
      final remainMs = (timerCompletesAtMs(timer) - nowMs).clamp(0, timer.durationMs);
      status = 'Growing · ${formatDurationMs(remainMs)} left';
    }
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14)),
              Text(status, style: TextStyle(color: chrome.embossFace, fontSize: 12.5)),
            ],
          ),
        ),
        GameButton(
          label: 'Travel',
          compact: true,
          onPressed: () => onTravel(spot.locationId, mapId),
        ),
      ],
    );
  }
}
