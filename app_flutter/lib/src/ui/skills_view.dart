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

/// Skills-page tile icon size. 2.2× the original 24px display, then another 2×.
const double skillTileIconSize = 24 * 2.2 * 2;

/// Every skill as a tile, with the totals they add up to along the bottom.
class SkillsView extends StatelessWidget {
  const SkillsView({super.key, required this.controller, this.onClose, this.showHeader = true});

  final GameController controller;
  final VoidCallback? onClose;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader)
          if (onClose != null)
            PageHeader(title: 'Skills', onClose: onClose!)
          else
            const Padding(
              padding: EdgeInsets.fromLTRB(10, 8, 10, 6),
              child: Text('Skills', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400)),
            ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                const columns = 4;
                const rows = 4;
                const gap = 5.0;
                final cellW = (constraints.maxWidth - gap * (columns - 1)) / columns;
                final cellH = (constraints.maxHeight - gap * (rows - 1)) / rows;
                final skills = controller.db.skills
                    .where((row) => row.releasePhase == 'Launch')
                    .toList();
                return GridView.count(
                  crossAxisCount: columns,
                  mainAxisSpacing: gap,
                  crossAxisSpacing: gap,
                  childAspectRatio: cellW > 0 && cellH > 0 ? cellW / cellH : 1,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final skill in skills)
                      _SkillTile(controller: controller, skillId: skill.skillId),
                  ],
                );
              },
            ),
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
    final tooltip = progress.atCap
        ? '$name · ${formatThousands(progress.totalXp)} total xp'
        : '$name · ${formatThousands(progress.totalXp)} total xp\n'
              '${formatThousands(needed - into)} xp to level ${progress.nextLevel}';
    return Tooltip(
      message: tooltip,
      child: GamePanel(
        padding: const EdgeInsets.fromLTRB(4, 5, 4, 4),
        child: InkWell(
          onTap: () => _openSkillMenu(context, controller, skillId, row?.displayName ?? skillId),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return FittedBox(
                fit: BoxFit.scaleDown,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GameImage(
                        skillIconPath(row),
                        width: skillTileIconSize,
                        height: skillTileIconSize,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        row?.displayName ?? skillId,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w400,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'Lv ${progress.level}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w400,
                          color: Palette.gold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      MeterBar(value: fraction, color: Palette.gold, height: 4),
                    ],
                  ),
                ),
              );
            },
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

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: UiChrome.of(context).slot,
        border: const Border(top: BorderSide(color: Palette.edge)),
      ),
      child: Row(
        children: [
          _Total(label: 'Combat level', value: formatThousands(combatLevelOf(save))),
          _Total(label: 'Total level', value: formatThousands(totalLevel(save))),
          _Total(label: 'Total xp', value: formatThousands(totalSkillXp(save))),
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
