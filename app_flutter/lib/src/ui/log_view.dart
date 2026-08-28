import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../content/asset_paths.dart';
import '../session/game_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'game_image.dart';
import 'page_header.dart';

enum _LogTab {
  achievements('Deeds', 'Deeds unlocked on this save.', 'achievements'),
  milestones('Milestones', 'Lifetime marks this save has reached.', 'milestones'),
  quests('Quests', 'Quest log for this save.', 'quests'),
  critters('Critters', 'Critters found while working their habitats.', 'critters');

  const _LogTab(this.label, this.lead, this.section);

  final String label;
  final String lead;

  /// Which section of [logCompletion] counts this page.
  final String section;
}

/// What this save has done: milestones, quests, and critters met.
class LogView extends StatefulWidget {
  const LogView({super.key, required this.controller, this.onClose});

  final GameController controller;
  final VoidCallback? onClose;

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
    final completion = logCompletion(db, save);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.onClose != null)
          PageHeader(
            title: 'Log',
            onClose: widget.onClose!,
            trailing: Text(
              '${jsNumberToString(completion.overall.percent)}% complete',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w400,
                color: Palette.gold,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const Text('Log', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w400)),
                Text(
                  '${jsNumberToString(completion.overall.percent)}% complete',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w400,
                    color: Palette.gold,
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              for (final tab in _LogTab.values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: GameButton(
                      label: tab.label,
                      compact: true,
                      selected: _tab == tab,
                      tone: _tab == tab ? GameButtonTone.primary : GameButtonTone.secondary,
                      onPressed: () => setState(() => _tab = tab),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Expanded(child: MutedText(_tab.lead)),
              if (completion.section(_tab.section) case final section?) ...[
                const SizedBox(width: 8),
                Text(
                  section.label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: Palette.gold,
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              switch (_tab) {
                _LogTab.achievements => _AchievementBands(rows: achievementLog(db, save)),
                _LogTab.milestones => _Rows([
                  for (final row in milestoneLog(db, save))
                    _LogRow(
                      title: row.name,
                      detail: row.note,
                      highlight: row.unlocked,
                      dimmed: !row.unlocked,
                    ),
                ]),
                _LogTab.quests => _Rows([
                  for (final row in questLog(db, save)) _QuestJournalRow(row: row),
                ]),
                _LogTab.critters => _Rows([
                  for (final row in critterLog(save))
                    _LogRow(
                      title: row.name,
                      detail: row.description,
                      trailing: row.count > 1 ? '×${formatThousands(row.count)}' : null,
                      highlight: row.found,
                      leading: row.found
                          ? GameImage(critterAssetPath(row.internalKey), width: 28, height: 28)
                          : const Icon(Icons.help_outline, size: 24, color: Palette.edge),
                    ),
                ]),
              },
            ],
          ),
        ),
      ],
    );
  }
}

class _AchievementBands extends StatelessWidget {
  const _AchievementBands({required this.rows});

  final List<AchievementLogRow> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final difficulty in achievementDifficulties)
          _DifficultyBand(
            difficulty: difficulty,
            rows: achievementLogForDifficulty(rows, difficulty),
            completion: achievementDifficultyCompletion(rows, difficulty),
          ),
      ],
    );
  }
}

class _DifficultyBand extends StatelessWidget {
  const _DifficultyBand({required this.difficulty, required this.rows, required this.completion});

  final String difficulty;
  final List<AchievementLogRow> rows;
  final LogSectionCompletion completion;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GamePanel(
        padding: EdgeInsets.zero,
        child: Material(
          type: MaterialType.transparency,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: difficulty == 'Easy',
              tilePadding: const EdgeInsets.symmetric(horizontal: 12),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              title: Text(
                difficulty,
                style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 16),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MutedText(completion.label),
                    const SizedBox(height: 4),
                    MeterBar(
                      value: completion.total <= 0 ? 0 : completion.done / completion.total,
                      color: Palette.gold,
                      height: 6,
                    ),
                  ],
                ),
              ),
              children: [
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _LogRow(
                      title: row.name,
                      detail: row.note,
                      highlight: row.unlocked,
                      dimmed: !row.unlocked,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
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
    this.highlight = false,
    this.dimmed = false,
  });

  final String title;
  final String? detail;

  /// A status or a count, on the right.
  final String? trailing;
  final Widget? leading;

  /// Gold title for anything the save has actually reached.
  final bool highlight;

  /// Greys the whole row out, for something not earned yet.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final row = _body();
    return dimmed ? Opacity(opacity: 0.45, child: row) : row;
  }

  Widget _body() {
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
                    fontWeight: FontWeight.w400,
                    color: highlight ? Palette.gold : Palette.parchmentText,
                  ),
                ),
                if (detail case final detail?) MutedText(detail),
              ],
            ),
          ),
          if (trailing case final trailing?) ...[const SizedBox(width: 8), MutedText(trailing)],
        ],
      ),
    );
  }
}

class _QuestJournalRow extends StatelessWidget {
  const _QuestJournalRow({required this.row});

  final QuestLogRow row;

  @override
  Widget build(BuildContext context) {
    final canOpen = row.steps.isNotEmpty;
    if (!canOpen) {
      return _LogRow(
        title: row.name,
        detail: row.detail,
        trailing: row.statusLabel,
        highlight: row.completed,
      );
    }

    return GamePanel(
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            title: Text(
              row.name,
              style: TextStyle(
                fontWeight: FontWeight.w400,
                color: row.completed ? Palette.gold : Palette.parchmentText,
              ),
            ),
            subtitle: MutedText(row.detail),
            trailing: MutedText(row.statusLabel),
            children: [
              for (final step in row.steps)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.state == 'done' ? '✓' : '•',
                        style: TextStyle(
                          color: step.state == 'done' ? Palette.softGreen : Palette.gold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          step.label,
                          style: TextStyle(
                            color: step.state == 'done' ? Palette.muted : Palette.parchmentText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
