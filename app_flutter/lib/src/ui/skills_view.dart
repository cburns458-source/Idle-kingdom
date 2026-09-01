import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../content/asset_paths.dart';
import '../session/game_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'game_image.dart';
import 'game_popup.dart';
import 'page_header.dart';
import 'skill_menu_sheet.dart';

/// Every skill as a tile, with the totals they add up to along the bottom.
class SkillsView extends StatelessWidget {
  const SkillsView({super.key, required this.controller, this.onClose, this.showHeader = true});

  final GameController controller;
  final VoidCallback? onClose;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final save = controller.save;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader)
          if (onClose != null)
            PageHeader(title: 'Skills', onClose: onClose!)
          else
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Text('Skills', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w400)),
            ),
        Expanded(
          child: GridView.extent(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            maxCrossAxisExtent: 96,
            mainAxisSpacing: 7,
            crossAxisSpacing: 7,
            childAspectRatio: 0.86,
            children: [
              for (final skill in save.skills)
                _SkillTile(controller: controller, skillId: skill.skillId),
            ],
          ),
        ),
        _Totals(controller: controller),
      ],
    );
  }
}

class _SkillTile extends StatelessWidget {
  const _SkillTile({required this.controller, required this.skillId});

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

    final name = row?.displayName ?? skillId;
    return Tooltip(
      message: progress.atCap
          ? '$name · mastered\n${formatThousands(progress.totalXp)} total xp'
          : '$name · ${formatThousands(progress.totalXp)} total xp\n'
                '${formatThousands(needed - into)} xp to level ${progress.nextLevel}',
      child: GamePanel(
        padding: const EdgeInsets.fromLTRB(5, 6, 5, 5),
        child: InkWell(
          onTap: () => _openSkillMenu(context, controller, skillId, row?.displayName ?? skillId),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GameImage(skillIconPath(row), width: 30, height: 30),
              const SizedBox(height: 3),
              Flexible(
                child: Text(
                  row?.displayName ?? skillId,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w400, height: 1.15),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                progress.atCap ? 'Max' : 'Lv ${progress.level}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: Palette.gold,
                ),
              ),
              const SizedBox(height: 3),
              MeterBar(value: fraction, color: Palette.gold, height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

void _openSkillMenu(
  BuildContext context,
  GameController controller,
  String skillId,
  String skillName,
) {
  showSkillMenuPopup(
    context: context,
    origin: popupOrigin(context),
    db: controller.db,
    save: controller.save,
    skillId: skillId,
    skillName: skillName,
  );
}

/// The bottom band: what every skill adds up to.
class _Totals extends StatelessWidget {
  const _Totals({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final save = controller.save;
    final mastered = save.skills.where((skill) {
      return skillXpProgress(controller.db, skill.xp).atCap;
    }).length;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        color: Palette.slot,
        border: Border(top: BorderSide(color: Palette.edge)),
      ),
      child: Row(
        children: [
          _Total(label: 'Total level', value: formatThousands(totalLevel(save))),
          _Total(label: 'Total xp', value: formatThousands(totalSkillXp(save))),
          _Total(label: 'Mastered', value: '$mastered / ${save.skills.length}'),
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MutedText(label),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w400)),
        ],
      ),
    );
  }
}
