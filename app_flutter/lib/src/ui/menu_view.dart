import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'save_transfer_section.dart';

/// Character identity and the save tools that used to live under Menu.
class MenuView extends StatelessWidget {
  const MenuView({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final save = controller.save;
    final raceName = raceDisplayName(controller.db, save.raceId);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Menu', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const MutedText('Settings and save tools.'),
        const SizedBox(height: 16),
        GamePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MutedText('Character'),
              const SizedBox(height: 4),
              Text(
                save.characterName ?? 'Unnamed',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              MutedText('Race: ${raceName ?? 'Unchosen'}'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SaveTransferSection(controller: controller),
      ],
    );
  }
}
