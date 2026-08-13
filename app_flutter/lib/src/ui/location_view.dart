import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../content/asset_paths.dart';
import '../session/game_controller.dart';
import '../theme.dart';
import 'activity_panel.dart';
import 'format.dart';

/// Where the player is standing: the art, what can be done here, and whatever
/// is currently running.
class LocationView extends StatelessWidget {
  const LocationView({super.key, required this.controller, required this.onOpenMap});

  final GameController controller;
  final VoidCallback onOpenMap;

  @override
  Widget build(BuildContext context) {
    final location = controller.location;
    if (location == null) {
      return const Center(child: Text('This place is not on any map.'));
    }
    final locationId = location.locationId;
    final activities = controller.indexes.activitiesByLocationId[locationId] ?? const [];

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          locationAssetPath(locationId),
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x33000000), Color(0xCC1F1610)],
              stops: [0.25, 1],
            ),
          ),
        ),
        ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // The art behind the text is busy, so the header carries its own panel.
            GamePanel(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    location.displayName,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  if (location.description case final blurb?) MutedText(blurb),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (controller.isRecovering) ...[
              _RecoveringPanel(controller: controller),
              const SizedBox(height: 10),
            ],
            if (controller.save.currentActivityId != null) ...[
              ActivityPanel(controller: controller),
              const SizedBox(height: 10),
            ],
            if (controller.activityError case final error?) ...[
              _Notice(text: error, tone: Palette.danger),
              const SizedBox(height: 10),
            ],
            if (controller.message case final message?) ...[
              _Notice(text: message, tone: Palette.gold),
              const SizedBox(height: 10),
            ],
            if (activities.isEmpty)
              const GamePanel(child: Text('Nothing to do here yet.'))
            else
              for (final activity in activities)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ActivityCard(controller: controller, activity: activity),
                ),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: onOpenMap, child: const Text('Open the map')),
          ],
        ),
      ],
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.controller, required this.activity});

  final GameController controller;
  final ActivityRow activity;

  @override
  Widget build(BuildContext context) {
    final activityId = activity.activityId;
    final running = controller.save.currentActivityId == activityId;
    final check = validateActivityStart(controller.db, controller.save, activityId);
    final production = isStandardProductionActivity(controller.db, activity);

    return GamePanel(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.contextualName ?? activityId,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (activity.description case final blurb?) MutedText(blurb),
                if (!check.ok) MutedText(check.reason ?? ''),
                // Recipes are picked in the production panel, which is not
                // ported yet, so the station is listed but not startable.
                if (production && check.ok)
                  const MutedText('Crafting comes with the workshop panel.'),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (running)
            OutlinedButton(onPressed: controller.stopActivity, child: const Text('Stop'))
          else
            FilledButton(
              onPressed: check.ok && !production
                  ? () => controller.startActivity(activityId)
                  : null,
              child: const Text('Start'),
            ),
        ],
      ),
    );
  }
}

class _RecoveringPanel extends StatelessWidget {
  const _RecoveringPanel({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return GamePanel(
      child: Row(
        children: [
          const Expanded(
            child: Text('Recovering', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          Text(
            'Resuming in ${formatDurationMs(controller.deathPauseRemainingMs)}',
            style: const TextStyle(color: Palette.danger),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.tone});

  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return GamePanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(text, style: TextStyle(color: tone, fontSize: 13)),
    );
  }
}
