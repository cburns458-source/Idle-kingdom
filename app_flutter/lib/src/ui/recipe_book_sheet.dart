import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import 'catalog_popup.dart';

/// Station-scoped recipe book: listed by skill level, locked rows stay in place.
Future<void> showStationRecipeBook(
  BuildContext context, {
  required String title,
  required List<RecipeLogRow> rows,
}) {
  return showGameCatalogPopup(
    context: context,
    eyebrow: 'Recipe book',
    title: title,
    emptyMessage: 'Nothing is written for this station yet.',
    entries: [
      for (final row in rows)
        CatalogPopupEntry(
          title: row.title,
          detail: row.detail,
          dimmed: !row.known,
          emphasized: row.known,
        ),
    ],
  );
}
