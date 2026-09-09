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
/// Lists discovered spots (even empty). Timers start at the location; Travel
/// appears only when a timer is Ready so you can go collect.
class TimersView extends StatefulWidget {
  const TimersView({super.key, required this.controller, this.onClose, this.onTravel});

  final GameController controller;
  final VoidCallback? onClose;

  /// Instant travel that should also open the location stage.
  final void Function(String locationId, String mapId)? onTravel;

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

  void _travel(String locationId, String mapId) {
    final travel = widget.onTravel;
    if (travel != null) {
      travel(locationId, mapId);
      return;
    }
    controller.travelTo(locationId, mapId);
  }

  List<_DiscoveredSpot> _spotsForKind(PlayerSave save, String kind) {
    final spots = <_DiscoveredSpot>[];
    for (final key in save.discoveredTimerSpotIds) {
      final parsed = parseTimerSpotKey(key);
      if (parsed == null || parsed.kind != kind) continue;
      final active = timerAtLocationKind(save, parsed.locationId, kind);
      spots.add(_DiscoveredSpot(kind: parsed.kind, locationId: parsed.locationId, timer: active));
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
        final here = save.currentLocationId;
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
                'Timers start at locations. Travel appears when a spot is ready to collect.',
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
                    currentLocationId: here,
                    onTravel: _travel,
                    save: save,
                  ),
                  const SizedBox(height: 12),
                  _TimerSection(
                    title: 'Hunting',
                    emptyLabel: 'No hunting traps discovered yet.',
                    spots: _spotsForKind(save, 'hunting_trap'),
                    db: db,
                    nowMs: nowMs,
                    currentLocationId: here,
                    onTravel: _travel,
                    save: save,
                  ),
                  const SizedBox(height: 12),
                  _TimerSection(
                    title: 'Fishing',
                    emptyLabel: 'No fishing pots discovered yet.',
                    spots: _spotsForKind(save, 'fishing_pot'),
                    db: db,
                    nowMs: nowMs,
                    currentLocationId: here,
                    onTravel: _travel,
                    save: save,
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
    required this.currentLocationId,
    required this.onTravel,
    required this.save,
  });

  final String title;
  final String emptyLabel;
  final List<_DiscoveredSpot> spots;
  final GameDatabase db;
  final num nowMs;
  final String currentLocationId;
  final void Function(String locationId, String mapId) onTravel;
  final PlayerSave save;

  @override
  Widget build(BuildContext context) {
    final chrome = UiChrome.of(context);
    return GamePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(fontWeight: FontWeight.w400, fontSize: 16, color: chrome.panelInk),
          ),
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
                child: _TimerRow(
                  spot: spot,
                  db: db,
                  nowMs: nowMs,
                  currentLocationId: currentLocationId,
                  onTravel: onTravel,
                  save: save,
                ),
              ),
        ],
      ),
    );
  }
}

class _TimerRow extends StatelessWidget {
  const _TimerRow({
    required this.spot,
    required this.db,
    required this.nowMs,
    required this.currentLocationId,
    required this.onTravel,
    required this.save,
  });

  final _DiscoveredSpot spot;
  final GameDatabase db;
  final num nowMs;
  final String currentLocationId;
  final void Function(String locationId, String mapId) onTravel;
  final PlayerSave save;

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
    final ready = timer != null && timerIsReady(timer, nowMs);
    final String status;
    if (timer == null) {
      if (spot.kind == 'fishing_pot') {
        final lock = fishingPotLockedUntilDay(save, spot.locationId, nowMs: nowMs);
        status = lock.locked
            ? 'Overfished · resets in ${formatDurationMs(lock.msRemaining)}'
            : 'Empty';
      } else {
        status = 'Empty';
      }
    } else if (ready) {
      status = 'Ready';
    } else {
      final remainMs = (timerCompletesAtMs(timer) - nowMs).clamp(0, timer.durationMs);
      status = 'Growing · ${formatDurationMs(remainMs)} left';
    }
    final showTravel = ready && spot.locationId != currentLocationId;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 14, color: chrome.panelInk)),
              Text(status, style: TextStyle(color: chrome.embossFace, fontSize: 12.5)),
            ],
          ),
        ),
        if (showTravel)
          GameButton(
            label: 'Travel',
            compact: true,
            onPressed: () => onTravel(spot.locationId, mapId),
          ),
      ],
    );
  }
}
