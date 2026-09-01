import 'package:flutter/material.dart';

import '../session/game_controller.dart';
import '../theme.dart';

/// Covers the game for the length of a journey.
class TravelOverlay extends StatelessWidget {
  const TravelOverlay({super.key, required this.controller, required this.journey});

  final GameController controller;
  final TravelInFlight journey;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[controller, controller.progress]),
      builder: (context, _) => _buildOverlay(context),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    String nameOf(String locationId) {
      return controller.indexes.locationsById[locationId]?.displayName ?? locationId;
    }

    return ColoredBox(
      color: const Color(0xE6120C08),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Travelling', style: TextStyle(fontSize: 20)),
              const SizedBox(height: 6),
              Text(
                '${nameOf(journey.fromLocationId)} → ${nameOf(journey.toLocationId)}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w400),
              ),
              const SizedBox(height: 14),
              MeterBar(value: controller.travelProgress, color: Palette.gold),
            ],
          ),
        ),
      ),
    );
  }
}
