import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../theme.dart';
import 'catalog_popup.dart';
import 'game_popup.dart';
import 'recipe_book_sheet.dart';

/// Tabbed skill catalog, with a recipe book for production skills.
Future<void> showSkillMenuPopup({
  required BuildContext context,
  required GameDatabase db,
  required PlayerSave save,
  required String skillId,
  required String skillName,
  Rect? origin,
}) {
  final view = skillMenuView(db, skillId);
  return showGamePopup<void>(
    context: context,
    origin: origin ?? popupOrigin(context),
    builder: (context) {
      return GamePopupCard(
        child: GamePanel(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
            child: _SkillMenuBody(
              db: db,
              save: save,
              skillId: skillId,
              skillName: skillName,
              view: view,
            ),
          ),
        ),
      );
    },
  );
}

class _SkillMenuBody extends StatefulWidget {
  const _SkillMenuBody({
    required this.db,
    required this.save,
    required this.skillId,
    required this.skillName,
    required this.view,
  });

  final GameDatabase db;
  final PlayerSave save;
  final String skillId;
  final String skillName;
  final SkillMenuView view;

  @override
  State<_SkillMenuBody> createState() => _SkillMenuBodyState();
}

class _SkillMenuBodyState extends State<_SkillMenuBody> {
  late String _tabId = widget.view.tabs.first.id;

  SkillMenuTab get _tab {
    return widget.view.tabs.firstWhere(
      (tab) => tab.id == _tabId,
      orElse: () => widget.view.tabs.first,
    );
  }

  void _openRecipeBook() {
    showStationRecipeBook(
      context,
      title: widget.skillName,
      rows: recipeLogForEntries(recipeBookForSkill(widget.save, widget.db, widget.skillId)),
      emptyMessage: "You haven't unlocked any recipes for this skill yet.",
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = [
      for (final section in _tab.sections) ...[
        if (section.title case final title?) CatalogPopupEntry(title: title, dimmed: true),
        for (final entry in section.entries) CatalogPopupEntry(title: skillMenuLine(entry)),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const MutedText('Skill'),
        Text(widget.skillName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400)),
        if (widget.view.tabs.length > 1) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tab in widget.view.tabs)
                GameButton(
                  label: tab.label,
                  compact: true,
                  selected: tab.id == _tab.id,
                  onPressed: () => setState(() => _tabId = tab.id),
                ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              if (entries.isEmpty)
                const MutedText('Nothing listed for this skill yet.')
              else
                for (final entry in entries) _SkillMenuRow(entry: entry),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (widget.view.showRecipeBook) ...[
          GameButton(
            label: 'Recipe book',
            tone: GameButtonTone.secondary,
            onPressed: _openRecipeBook,
          ),
          const SizedBox(height: 8),
        ],
        GameButton(label: 'Close', onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }
}

class _SkillMenuRow extends StatelessWidget {
  const _SkillMenuRow({required this.entry});

  final CatalogPopupEntry entry;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: entry.dimmed ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          entry.title,
          style: TextStyle(
            fontWeight: FontWeight.w400,
            color: entry.emphasized ? Palette.gold : Palette.parchmentText,
          ),
        ),
      ),
    );
  }
}
