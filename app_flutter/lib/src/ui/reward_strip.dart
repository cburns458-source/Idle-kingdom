import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../content/asset_paths.dart';
import '../session/game_controller.dart';
import '../theme.dart';

/// The last few completed actions, one row each: xp, gold, then loot.
class RewardStrip extends StatelessWidget {
  const RewardStrip({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final rows = controller.recentRewards.where(_hasContent).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final bundle in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: _RewardRow(bundle: bundle, controller: controller),
          ),
      ],
    );
  }

  static bool _hasContent(ActionRewardBundle bundle) {
    return bundle.xpRewards.isNotEmpty || bundle.loot.isNotEmpty || bundle.goldGained > 0;
  }
}

class _RewardRow extends StatelessWidget {
  const _RewardRow({required this.bundle, required this.controller});

  final ActionRewardBundle bundle;
  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final xp in bundle.xpRewards)
          _Chip(
            label: '${xp.xp}',
            iconPath: skillIconPath(controller.indexes.skillsById[xp.skillId]),
            tooltip: xp.skillName,
          ),
        if (bundle.goldGained > 0)
          _Chip(label: '+${bundle.goldGained}', iconPath: goldIconPath(), tooltip: 'Gold'),
        for (final loot in bundle.loot)
          _Chip(
            label: '${loot.quantity}',
            iconPath: itemIconPath(controller.indexes.itemsById[loot.itemId]),
            tooltip: loot.displayName,
          ),
        for (final levelUp in bundle.xpRewards.where((xp) => xp.leveledUp))
          Text(
            'level ${levelUp.level} ${levelUp.skillName} achieved',
            style: const TextStyle(fontSize: 12, color: Palette.gold),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.iconPath, required this.tooltip});

  final String label;
  final String iconPath;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0x44120C08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Palette.edge),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(width: 4),
            Image.asset(iconPath, width: 14, height: 14, filterQuality: FilterQuality.none),
          ],
        ),
      ),
    );
  }
}
