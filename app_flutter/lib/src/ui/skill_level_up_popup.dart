import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../theme.dart';
import 'game_popup.dart';

/// Quest-style card for a skill that just rose.
Future<void> showSkillLevelUp(BuildContext context, SkillLevelUpNotice notice, {UiChrome? chrome}) {
  return showGamePopup<void>(
    context: context,
    chrome: chrome,
    builder: (dialogContext) => GamePopupCard(
      child: GamePanel(
        framed: true,
        child: Builder(
          builder: (context) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const MutedText('Level up'),
                Text(
                  'Level ${notice.level} ${notice.skillName}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w400,
                    color: UiChrome.of(context).panelInk,
                  ),
                ),
                if (notice.unlocks.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ..._section(context, 'Unlocked', notice.unlocks.unlockedActivities),
                          ..._section(
                            context,
                            'Now proficient',
                            notice.unlocks.proficientActivities,
                          ),
                          ..._section(context, 'Recipes', notice.unlocks.recipes),
                          ..._section(context, 'Projects', notice.unlocks.projects),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                GameButton(label: 'Continue', onPressed: () => Navigator.of(dialogContext).pop()),
              ],
            );
          },
        ),
      ),
    ),
  );
}

List<Widget> _section(BuildContext context, String heading, List<String> names) {
  if (names.isEmpty) return const <Widget>[];
  final accent = UiChrome.of(context).embossFace;
  return [
    Padding(padding: const EdgeInsets.only(top: 6, bottom: 2), child: MutedText(heading)),
    for (final name in names)
      Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text('· $name', style: TextStyle(color: accent)),
      ),
  ];
}
