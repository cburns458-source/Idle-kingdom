import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'item_icon.dart';
import 'reward_strip.dart';

/// Name, race, totals, gold, HP, and the reward lines from the last few actions.
class TopHud extends StatelessWidget {
  const TopHud({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final save = controller.save;
    final maxHp = playerMaxHp(controller.db, save);
    final hpFraction = maxHp <= 0 ? 0.0 : (save.currentHp / maxHp).clamp(0, 1).toDouble();
    final raceName = raceDisplayName(controller.db, save.raceId);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Palette.edge)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      save.characterName ?? 'Adventurer',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    MutedText(raceName ?? 'Unsworn'),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  MutedText('Total level ${totalLevel(save)}'),
                  GoldAmount(
                    amount: save.gold,
                    size: 16,
                    style: const TextStyle(color: Palette.gold, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: MeterBar(value: hpFraction, color: Palette.softGreen, height: 10),
              ),
              const SizedBox(width: 8),
              Text(
                controller.isRecovering
                    ? 'Dead'
                    : '${formatThousands(save.currentHp)}/${formatThousands(maxHp)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: controller.isRecovering ? Palette.danger : Palette.parchmentText,
                ),
              ),
            ],
          ),
          if (controller.recentRewards.isNotEmpty) ...[
            const SizedBox(height: 6),
            RewardStrip(controller: controller),
          ],
        ],
      ),
    );
  }
}
