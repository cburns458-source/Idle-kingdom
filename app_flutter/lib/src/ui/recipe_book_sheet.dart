import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../theme.dart';
import 'catalog_popup.dart';
import 'game_popup.dart';

/// Station or skill recipe book: listed by skill level, locked rows stay in place.
///
/// When [db] is provided, rows are grouped with the same tabs as the skill menu.
/// Production / project pickers stay flat — only this popup is tabbed.
Future<void> showStationRecipeBook(
  BuildContext context, {
  required String title,
  List<RecipeLogRow>? rows,
  List<RecipeBookEntry>? entries,
  GameDatabase? db,
  String? skillId,
  String emptyMessage = 'Nothing is written for this station yet.',
}) {
  final bookEntries = entries ?? const <RecipeBookEntry>[];
  final resolvedSkillId = skillId ?? (db != null ? recipeBookSkillId(db, bookEntries) : null);
  final view = db != null && resolvedSkillId != null
      ? recipeBookViewForEntries(db, resolvedSkillId, bookEntries)
      : null;
  final useTabs = view != null && (view.tabs.length > 1 || _hasSectionTitles(view));

  if (!useTabs) {
    final logRows = rows ?? recipeLogForEntries(bookEntries);
    return showGameCatalogPopup(
      context: context,
      eyebrow: 'Recipe book',
      title: title,
      emptyMessage: emptyMessage,
      entries: [
        for (final row in logRows)
          CatalogPopupEntry(
            title: row.title,
            detail: row.detail.isEmpty ? null : row.detail,
            dimmed: !row.known,
            emphasized: row.known,
          ),
      ],
    );
  }

  return showGamePopup<void>(
    context: context,
    origin: popupOrigin(context),
    builder: (context) {
      return GamePopupCard(
        child: GamePanel(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
            child: _RecipeBookBody(title: title, view: view, emptyMessage: emptyMessage),
          ),
        ),
      );
    },
  );
}

bool _hasSectionTitles(RecipeBookView view) {
  return view.tabs.any(
    (tab) => tab.sections.any((section) => section.title != null && section.title!.isNotEmpty),
  );
}

class _RecipeBookBody extends StatefulWidget {
  const _RecipeBookBody({required this.title, required this.view, required this.emptyMessage});

  final String title;
  final RecipeBookView view;
  final String emptyMessage;

  @override
  State<_RecipeBookBody> createState() => _RecipeBookBodyState();
}

class _RecipeBookBodyState extends State<_RecipeBookBody> {
  late String _tabId = widget.view.tabs.first.id;

  RecipeBookTab get _tab {
    return widget.view.tabs.firstWhere(
      (tab) => tab.id == _tabId,
      orElse: () => widget.view.tabs.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = <CatalogPopupEntry>[
      for (final section in _tab.sections) ...[
        if (section.title case final title?) CatalogPopupEntry(title: title, dimmed: true),
        for (final entry in section.entries) _entryFromBook(entry),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const MutedText('Recipe book'),
        Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400)),
        if (widget.view.tabs.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              for (var index = 0; index < widget.view.tabs.length; index++) ...[
                if (index > 0) const SizedBox(width: 6),
                Expanded(
                  child: GameButton(
                    label: widget.view.tabs[index].label,
                    compact: true,
                    dense: widget.view.tabs.length > 2,
                    selected: widget.view.tabs[index].id == _tab.id,
                    tone: widget.view.tabs[index].id == _tab.id
                        ? GameButtonTone.primary
                        : GameButtonTone.secondary,
                    onPressed: () => setState(() => _tabId = widget.view.tabs[index].id),
                  ),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: 10),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              if (rows.isEmpty)
                MutedText(widget.emptyMessage)
              else
                for (final entry in rows) _RecipeBookRow(entry: entry),
            ],
          ),
        ),
        const SizedBox(height: 8),
        GameButton(label: 'Close', onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }
}

CatalogPopupEntry _entryFromBook(RecipeBookEntry entry) {
  final row = recipeLogRowFromEntry(entry);
  return CatalogPopupEntry(
    title: row.title,
    detail: row.detail.isEmpty ? null : row.detail,
    dimmed: !row.known,
    emphasized: row.known,
  );
}

class _RecipeBookRow extends StatelessWidget {
  const _RecipeBookRow({required this.entry});

  final CatalogPopupEntry entry;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: entry.dimmed ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              entry.title,
              style: TextStyle(
                fontWeight: FontWeight.w400,
                color: entry.emphasized ? Palette.gold : UiChrome.of(context).panelInk,
              ),
            ),
            if (entry.detail case final detail?) MutedText(detail),
          ],
        ),
      ),
    );
  }
}
