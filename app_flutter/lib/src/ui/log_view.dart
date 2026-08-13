import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../content/asset_paths.dart';
import '../session/game_controller.dart';
import '../theme.dart';
import 'format.dart';

enum _LogTab {
  achievements('Achievements', 'Skill milestones unlocked on this save.'),
  quests('Quests', 'Quest log for this save.'),
  recipes('Recipe Book', 'Known recipes and special projects for this save.'),
  critters('Critters', 'Critters found while working their habitats.');

  const _LogTab(this.label, this.lead);

  final String label;
  final String lead;
}

/// What this save has done: milestones, quests, recipes learned, critters met.
class LogView extends StatefulWidget {
  const LogView({super.key, required this.controller});

  final GameController controller;

  @override
  State<LogView> createState() => _LogViewState();
}

class _LogViewState extends State<LogView> {
  _LogTab _tab = _LogTab.achievements;

  GameController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final db = controller.db;
    final save = controller.save;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Log', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<_LogTab>(
            segments: [
              for (final tab in _LogTab.values) ButtonSegment(value: tab, label: Text(tab.label)),
            ],
            selected: {_tab},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => setState(() => _tab = selection.first),
          ),
        ),
        const SizedBox(height: 8),
        MutedText(_tab.lead),
        const SizedBox(height: 8),
        switch (_tab) {
          _LogTab.achievements => _Rows([
            for (final row in achievementLog(db, save))
              _LogRow(title: row.name, detail: row.note, highlight: row.unlocked),
          ]),
          _LogTab.quests => _Rows([
            for (final row in questLog(db, save))
              _LogRow(
                title: row.name,
                detail: row.detail,
                trailing: row.statusLabel,
                highlight: row.completed,
                below: [
                  for (final objective in row.objectives) _ObjectiveBar(objective: objective),
                ],
              ),
          ]),
          _LogTab.recipes => _Rows([
            for (final row in recipeLog(db, save))
              _LogRow(title: row.title, detail: row.detail, highlight: row.known),
          ]),
          _LogTab.critters => _Rows([
            for (final row in critterLog(save))
              _LogRow(
                title: row.name,
                detail: row.description,
                trailing: row.count > 1 ? '×${formatThousands(row.count)}' : null,
                highlight: row.found,
                leading: row.found
                    ? Image.asset(
                        critterAssetPath(row.internalKey),
                        width: 28,
                        height: 28,
                        filterQuality: FilterQuality.none,
                      )
                    : const Icon(Icons.help_outline, size: 24, color: Palette.edge),
              ),
          ]),
        },
      ],
    );
  }
}

class _Rows extends StatelessWidget {
  const _Rows(this.rows);

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows) Padding(padding: const EdgeInsets.only(bottom: 8), child: row),
      ],
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({
    required this.title,
    required this.detail,
    this.trailing,
    this.leading,
    this.below = const [],
    this.highlight = false,
  });

  final String title;
  final String? detail;

  /// A status or a count, on the right.
  final String? trailing;
  final Widget? leading;

  /// Progress bars and the like, under the copy.
  final List<Widget> below;

  /// Gold title for anything the save has actually reached.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return GamePanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading case final leading?) ...[leading, const SizedBox(width: 10)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: highlight ? Palette.gold : Palette.parchmentText,
                  ),
                ),
                if (detail case final detail?) MutedText(detail),
                ...below,
              ],
            ),
          ),
          if (trailing case final trailing?) ...[const SizedBox(width: 8), MutedText(trailing)],
        ],
      ),
    );
  }
}

class _ObjectiveBar extends StatelessWidget {
  const _ObjectiveBar({required this.objective});

  final QuestLogObjective objective;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MutedText(objective.label),
          const SizedBox(height: 2),
          MeterBar(value: objective.percent / 100, color: Palette.softGreen, height: 6),
        ],
      ),
    );
  }
}
