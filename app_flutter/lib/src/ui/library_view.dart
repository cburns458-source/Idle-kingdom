import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'game_popup.dart';
import 'page_header.dart';

/// Unlocked books from quests and drops. Never inventory items.
class LibraryView extends StatelessWidget {
  const LibraryView({super.key, required this.controller, this.onClose});

  final GameController controller;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final books = libraryBookRows(controller.db, controller.save);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (onClose != null)
              PageHeader(title: 'Library', onClose: onClose!)
            else
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Text('Library', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w400)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: MutedText(
                books.isEmpty
                    ? 'Books you find will be kept here.'
                    : 'Tap a book to read it.',
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: books.isEmpty
                  ? const Center(child: MutedText('No books yet.'))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: books.length,
                      itemBuilder: (context, index) {
                        final book = books[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GamePanel(
                            child: InkWell(
                              onTap: () => _openBook(context, book),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Text(
                                  book.displayName,
                                  style: const TextStyle(fontWeight: FontWeight.w400),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openBook(BuildContext context, BookRow book) async {
    await showGamePopup<void>(
      context: context,
      builder: (context) {
        return GamePopupCard(
          title: book.displayName,
          child: SingleChildScrollView(
            child: Text(book.body, style: const TextStyle(height: 1.35)),
          ),
          actions: [
            GameButton(
              label: 'Close',
              tone: GameButtonTone.secondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }
}

/// Popup when a book is first unlocked into the Library.
class LibraryUnlockPopup extends StatelessWidget {
  const LibraryUnlockPopup({
    super.key,
    required this.notice,
    required this.onClose,
  });

  final BookUnlockNotice notice;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xCC120C08),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: GamePanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const MutedText('New Book'),
                const Text(
                  'You found a book!',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w400),
                ),
                const SizedBox(height: 10),
                Text(notice.name, style: const TextStyle(fontWeight: FontWeight.w400)),
                const SizedBox(height: 10),
                const Text('It has been added to your Library.'),
                if (notice.hint case final hint?) ...[const SizedBox(height: 6), MutedText(hint)],
                const SizedBox(height: 14),
                GameButton(label: 'Nice!', onPressed: onClose),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
