import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../content/asset_paths.dart';
import '../session/game_controller.dart';
import '../theme.dart';

/// Every skill with its level and progress to the next one.
class SkillsView extends StatelessWidget {
  const SkillsView({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final save = controller.save;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Skills', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            MutedText('Total level ${totalLevel(save)}'),
          ],
        ),
        const SizedBox(height: 8),
        for (final skill in save.skills)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SkillRow(controller: controller, skillId: skill.skillId),
          ),
      ],
    );
  }
}

class _SkillRow extends StatelessWidget {
  const _SkillRow({required this.controller, required this.skillId});

  final GameController controller;
  final String skillId;

  @override
  Widget build(BuildContext context) {
    final row = controller.indexes.skillsById[skillId];
    final stored = getSkillProgress(controller.save, skillId);
    final progress = skillXpProgress(controller.db, stored.xp);
    final into = progress.intoLevel;
    final needed = progress.toNextLevel;
    final fraction = needed <= 0 ? 1.0 : (into / needed).clamp(0, 1).toDouble();

    return GamePanel(
      child: Row(
        children: [
          Image.asset(skillIconPath(row), width: 28, height: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        row?.raw['Display Name'] as String? ?? skillId,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text('Level ${progress.level}'),
                  ],
                ),
                const SizedBox(height: 4),
                MeterBar(value: fraction, color: Palette.gold, height: 6),
                const SizedBox(height: 2),
                MutedText(progress.atCap ? 'Mastered' : '${into.round()} / ${needed.round()} xp'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
