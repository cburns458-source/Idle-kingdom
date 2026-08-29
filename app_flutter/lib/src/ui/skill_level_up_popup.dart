import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../theme.dart';
import 'game_popup.dart';

/// Quest-style card for a skill that just rose.
Future<void> showSkillLevelUp(BuildContext context, SkillLevelUpNotice notice) {
  return showGamePopup<void>(
    context: context,
    builder: (context) => GamePopupCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const MutedText('Level up'),
          Text(
            'Level ${notice.level} ${notice.skillName}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400),
          ),
          if (notice.unlocks.isNotEmpty) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ..._section('Unlocked', notice.unlocks.unlockedActivities),
                    ..._section('Now proficient', notice.unlocks.proficientActivities),
                    ..._section('Recipes', notice.unlocks.recipes),
                    ..._section('Projects', notice.unlocks.projects),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          GameButton(label: 'Continue', onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    ),
  );
}

List<Widget> _section(String heading, List<String> names) {
  if (names.isEmpty) return const <Widget>[];
  return [
    Padding(padding: const EdgeInsets.only(top: 6, bottom: 2), child: MutedText(heading)),
    for (final name in names)
      Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text('· $name', style: const TextStyle(color: Palette.gold)),
      ),
  ];
}
