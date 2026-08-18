import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../theme.dart';

/// Station-scoped recipe book: known rows in gold, locked rows still named.
Future<void> showStationRecipeBook(
  BuildContext context, {
  required String title,
  required List<RecipeLogRow> rows,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: GamePanel(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const MutedText('Recipe book'),
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        if (rows.isEmpty)
                          const MutedText('Nothing is written for this station yet.')
                        else
                          for (final row in rows)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Opacity(
                                opacity: row.known ? 1 : 0.55,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      row.title,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: row.known ? Palette.gold : Palette.parchmentText,
                                      ),
                                    ),
                                    MutedText(row.detail),
                                  ],
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
