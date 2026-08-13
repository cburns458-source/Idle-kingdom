import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'format.dart';

/// The running activity: what is being done, how far along it is, and — in a
/// fight — who is hitting whom.
class ActivityPanel extends StatelessWidget {
  const ActivityPanel({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final save = controller.save;
    final activityId = save.currentActivityId;
    if (activityId == null) return const SizedBox.shrink();
    final activity = controller.indexes.activitiesById[activityId];
    final action = save.currentActionId == null
        ? null
        : controller.indexes.actionsById[save.currentActionId!];

    return GamePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  activity?.contextualName ?? activityId,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              OutlinedButton(onPressed: controller.stopActivity, child: const Text('Stop')),
            ],
          ),
          if (save.productionRecipeId case final recipeId?)
            MutedText(_queueLine(controller, recipeId))
          else if (action != null)
            MutedText(action.displayName),
          if (save.combatEnemyId != null)
            _CombatLine(controller: controller)
          else
            _ActionProgress(controller: controller),
        ],
      ),
    );
  }
}

/// "Copper Bar · 3/10 · 7m 30s left" for a running craft queue.
///
/// The time left counts the craft in progress plus the ones still queued behind
/// it, which is the number a player is actually waiting on.
String _queueLine(GameController controller, String recipeId) {
  final save = controller.save;
  final recipe = getRecipe(controller.db, recipeId);
  final total = save.productionQuantityTotal ?? 0;
  final remaining = save.productionQuantityRemaining ?? 0;
  final craftMs = save.actionDurationMs ?? 0;
  final leftOfCurrent = craftMs * (1 - controller.actionProgress);
  final queuedAfter = remaining > 0 ? remaining - 1 : 0;
  final name = recipe?.displayName ?? recipeId;
  return '$name · ${total - remaining}/$total · '
      '${formatDurationMs(leftOfCurrent + queuedAfter * craftMs)} left';
}

class _ActionProgress extends StatelessWidget {
  const _ActionProgress({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final durationMs = controller.save.actionDurationMs ?? 0;
    final progress = controller.actionProgress;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MeterBar(value: progress, color: Palette.softGreen),
          const SizedBox(height: 4),
          MutedText('${formatDurationMs(durationMs * progress)} / ${formatDurationMs(durationMs)}'),
        ],
      ),
    );
  }
}

class _CombatLine extends StatelessWidget {
  const _CombatLine({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final save = controller.save;
    final enemy = getEnemy(controller.db, save.combatEnemyId!);
    final enemyMaxHp = enemy?.maximumHp ?? 0;
    final enemyHp = save.combatEnemyHp ?? 0;
    final fraction = enemyMaxHp <= 0 ? 0.0 : (enemyHp / enemyMaxHp).clamp(0, 1).toDouble();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  enemy?.displayName ?? save.combatEnemyId!,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              MutedText('${enemyHp.round()} / ${enemyMaxHp.round()}'),
            ],
          ),
          const SizedBox(height: 4),
          MeterBar(value: fraction, color: Palette.danger),
          if (controller.message case final line?) ...[
            const SizedBox(height: 6),
            Text(line, style: const TextStyle(fontSize: 12)),
          ],
        ],
      ),
    );
  }
}
