import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'duration_text.dart';

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
                  activity?.raw['Contextual Name'] as String? ?? activityId,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              OutlinedButton(onPressed: controller.stopActivity, child: const Text('Stop')),
            ],
          ),
          if (action != null)
            MutedText(action.raw['Display Name'] as String? ?? save.currentActionId!),
          if (save.combatEnemyId != null)
            _CombatLine(controller: controller)
          else
            _ActionProgress(controller: controller),
        ],
      ),
    );
  }
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
    final enemyMaxHp = enemy == null ? 0 : jsNumberOrZero(enemy.raw['Max HP']);
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
                  enemy?.raw['Display Name'] as String? ?? save.combatEnemyId!,
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
