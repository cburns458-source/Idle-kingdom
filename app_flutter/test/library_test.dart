import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/ui/game_popup.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  testWidgets('Library lists unlocked books and opens the reader', (tester) async {
    final granted = grantBook(startedCharacter(database), 'BOOK-0001').save;
    final controller = buildController(database, seed: granted);
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(420, 900));

    await openChinScreen(tester, 'Library');
    expect(find.text("Newcomer's Guide"), findsOne);
    await tapVisible(tester, find.text("Newcomer's Guide"));
    expect(find.byType(GamePopupCard), findsOne);
    expect(find.textContaining('Welcome to Restoria'), findsOne);
  });

  testWidgets('unlocking a book pops the Library notice', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    controller.noteBookUnlocks(const [QuestBookGrant(bookId: 'BOOK-0001', isFirstEver: true)]);
    await tester.pump();

    expect(find.text('You found a book!'), findsOne);
    expect(find.text("Newcomer's Guide"), findsOne);
    expect(find.textContaining('Open Library from the menu'), findsOne);

    await tester.tap(find.text('Nice!'));
    await tester.pump();
    expect(find.text('You found a book!'), findsNothing);
  });
}
