import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../theme.dart';
import 'format.dart';
import 'item_icon.dart';

/// One running gold bar for hall room tiers. Marks sit at Sys's thresholds.
class GuildHallGoldBar extends StatelessWidget {
  const GuildHallGoldBar({super.key, required this.contributed});

  final num contributed;

  num get remaining => guildHallGoldRemaining(contributed);

  @override
  Widget build(BuildContext context) {
    final cap = guildHallGoldCap.toDouble();
    final t = cap <= 0 ? 0.0 : (contributed.toDouble() / cap).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          key: const Key('guild-gold-bar'),
          height: 16,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Palette.panel,
                      border: Border.all(color: Palette.goldShade),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: t,
                    child: Container(color: Palette.gold.withValues(alpha: 0.7)),
                  ),
                  for (final mark in guildHallGoldMarks)
                    Positioned(
                      key: Key('guild-gold-mark-${mark.round()}'),
                      left: constraints.maxWidth * (mark.toDouble() / cap) - 1,
                      top: 0,
                      bottom: 0,
                      child: Container(width: 2, color: Palette.goldShade),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        GoldAmount(
          key: const Key('guild-gold-remaining'),
          amount: remaining,
          style: const TextStyle(color: Palette.gold),
        ),
      ],
    );
  }
}

/// Gold still to chip in, as the bar shows it.
String guildHallGoldRemainingLabel(num contributed) =>
    formatThousands(guildHallGoldRemaining(contributed));

/// Largest chip-in the hall and the purse will both take. Zero when either is.
int guildHallGoldPayMax(num contributed, num playerGold) {
  final room = guildHallGoldChipInCap(contributed).floor();
  final purse = playerGold.floor();
  if (room <= 0 || purse <= 0) return 0;
  return room < purse ? room : purse;
}
