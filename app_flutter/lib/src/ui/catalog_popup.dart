import 'package:flutter/material.dart';

import '../theme.dart';
import 'game_popup.dart';

/// One row in a recipe-book-style catalog.
class CatalogPopupEntry {
  const CatalogPopupEntry({
    required this.title,
    this.detail,
    this.enabled = true,
    this.dimmed = false,
    this.emphasized = false,
  });

  final String title;
  final String? detail;
  final bool enabled;
  final bool dimmed;
  final bool emphasized;
}

/// Shared chrome for the recipe book, recipe picker, and skill menus.
Future<int?> showGameCatalogPopup({
  required BuildContext context,
  required String eyebrow,
  required String title,
  required List<CatalogPopupEntry> entries,
  String emptyMessage = 'Nothing listed yet.',
  bool selectable = false,
  String closeLabel = 'Close',
  Rect? origin,
}) {
  return showGamePopup<int>(
    context: context,
    origin: origin ?? popupOrigin(context),
    builder: (context) {
      return GamePopupCard(
        child: GamePanel(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                MutedText(eyebrow),
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400)),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      if (entries.isEmpty)
                        MutedText(emptyMessage)
                      else
                        for (var index = 0; index < entries.length; index++)
                          _CatalogRow(
                            entry: entries[index],
                            onTap: selectable && entries[index].enabled
                                ? () => Navigator.of(context).pop(index)
                                : null,
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                GameButton(label: closeLabel, onPressed: () => Navigator.of(context).pop()),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _CatalogRow extends StatelessWidget {
  const _CatalogRow({required this.entry, this.onTap});

  final CatalogPopupEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final body = Opacity(
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
                color: entry.emphasized ? Palette.gold : Palette.parchmentText,
              ),
            ),
            if (entry.detail case final detail?) MutedText(detail),
          ],
        ),
      ),
    );
    if (onTap == null) return body;
    return InkWell(onTap: onTap, child: body);
  }
}
