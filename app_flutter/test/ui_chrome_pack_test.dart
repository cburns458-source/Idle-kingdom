import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/ui_chrome.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:ik_content/ik_content.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  testWidgets('Settings General offers Wood and Stone UI looks', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(900, 2400));
    await tester.pump();

    expect(controller.uiChromePack, UiChromePack.wood);

    await openChinScreen(tester, 'Settings');
    await tester.scrollUntilVisible(
      find.text('UI look'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.text('UI look'), findsOneWidget);
    expect(find.text('Stone'), findsOneWidget);

    await tester.tap(find.widgetWithText(GameButton, 'Stone'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.uiChromePack, UiChromePack.stone);

    await tester.tap(find.widgetWithText(GameButton, 'Wood'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.uiChromePack, UiChromePack.wood);
  });

  /// Solid-color plate shots (no tiled assets) so rasterization cannot hang
  /// waiting on unresolved [AssetImage]s in widget tests.
}
