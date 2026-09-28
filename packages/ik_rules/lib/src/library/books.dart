import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../save/generated/save_models.dart';

BookRow? bookById(GameDatabase db, String bookId) {
  return db.books.firstWhereOrNull((row) => row.bookId == bookId);
}

bool isBookUnlocked(PlayerSave save, String bookId) {
  return save.unlockedBookIds.contains(bookId);
}

/// Unlock a book into the Library (idempotent). Books never enter the bag.
({PlayerSave save, bool granted, bool isFirstEver}) grantBook(PlayerSave save, String bookId) {
  final unlocked = save.unlockedBookIds;
  if (unlocked.contains(bookId)) {
    return (save: save, granted: false, isFirstEver: false);
  }
  return (
    save: save.copyWith(unlockedBookIds: [...unlocked, bookId]),
    granted: true,
    isFirstEver: unlocked.isEmpty,
  );
}

class BookUnlockNotice {
  const BookUnlockNotice({required this.bookId, required this.name, this.hint});

  final String bookId;
  final String name;
  final String? hint;

  Map<String, Object?> toJson() => <String, Object?>{'bookId': bookId, 'name': name, 'hint': hint};
}

const String libraryHint = 'Open Library from the menu to read your books anytime.';

BookUnlockNotice? bookUnlockNotice(GameDatabase db, String bookId, bool isFirstEver) {
  final book = bookById(db, bookId);
  if (book == null) return null;
  return BookUnlockNotice(
    bookId: bookId,
    name: book.displayName,
    hint: isFirstEver ? libraryHint : null,
  );
}

List<BookRow> libraryBookRows(GameDatabase db, PlayerSave save) {
  final unlocked = save.unlockedBookIds.toSet();
  final rows = db.books.where((row) => unlocked.contains(row.bookId)).toList();
  rows.sort((a, b) => a.displayName.compareTo(b.displayName));
  return rows;
}
