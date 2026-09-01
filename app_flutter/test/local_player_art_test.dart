import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/game_controller.dart';
import 'package:idle_kingdoms/src/session/local_player_art.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/top_hud.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

import 'support/harness.dart';
import 'support/tiny_png.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  test('a PNG under the cap is kept, and a reload reads it back', () {
    final storage = MemorySaveStorage();
    final art = LocalPlayerArt(storage: storage);
    expect(art.setPng(tinyPngBytes), isNull);
    expect(art.hasOverride, isTrue);
    expect(storage.getItem(LocalPlayerArt.storageKey), isNotNull);

    final reloaded = LocalPlayerArt.load(storage);
    expect(reloaded.bytes, tinyPngBytes);
  });

  test('a non-PNG and an oversized file are refused', () {
    final art = LocalPlayerArt();
    expect(art.setPng(Uint8List.fromList(const [1, 2, 3, 4])), LocalPlayerArt.notPngMessage);

    final oversized = Uint8List(LocalPlayerArt.maxBytes + 1);
    oversized.setAll(0, tinyPngBytes);
    expect(art.setPng(oversized), LocalPlayerArt.tooLargeMessage);
    expect(art.hasOverride, isFalse);
  });

  test('the override is stored beside the save, not inside it', () {
    final storage = MemorySaveStorage();
    final clock = TestClock();
    final repository = SaveRepository(storage: storage, clock: clock.read);
    repository.write(startedCharacter(database));
    final session = GameSession(
      db: database.launch,
      repository: repository,
      clock: clock.read,
      random: () => 0,
    );
    final controller = GameController(
      database: database,
      session: session,
      localArt: LocalPlayerArt(storage: storage),
    )..adoptBoot(session.boot());
    addTearDown(controller.dispose);

    expect(controller.applyLocalPlayerPng(tinyPngBytes), isNull);
    final saveRaw = storage.getItem(saveStorageKey)!;
    expect(saveRaw.contains(base64Encode(tinyPngBytes)), isFalse);
    expect(storage.getItem(LocalPlayerArt.storageKey), isNotEmpty);
  });

  testWidgets('Settings offers a PNG override that the HUD portrait uses', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(900, 2400));
    await openChinScreen(tester, 'Settings');
    await tester.tap(find.text('Testing'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Player sprite'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    expect(find.text('Player sprite'), findsOne);
    expect(find.bySemanticsLabel('Use my PNG'), findsOne);
    expect(
      tester.widget<GameButton>(find.widgetWithText(GameButton, 'Reset to default')).onPressed,
      isNull,
    );

    await tester.tap(find.bySemanticsLabel('Use my PNG'));
    await tester.pump();
    expect(find.text('PNG upload is available in the web client.'), findsOne);

    expect(controller.applyLocalPlayerPng(tinyPngBytes), isNull);
    await tester.pump();

    expect(
      tester.widget<GameButton>(find.widgetWithText(GameButton, 'Reset to default')).onPressed,
      isNotNull,
    );
    expect(
      find.descendant(of: find.byType(HudPortrait), matching: find.byWidgetPredicate(_memoryImage)),
      findsOne,
    );

    await tester.scrollUntilVisible(
      find.bySemanticsLabel('Reset to default'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.bySemanticsLabel('Reset to default'));
    await tester.pump();

    expect(controller.localPlayerPng, isNull);
    expect(
      find.descendant(of: find.byType(HudPortrait), matching: find.byWidgetPredicate(_memoryImage)),
      findsNothing,
    );
    expect(find.text('Back to the default adventurer.'), findsOne);
  });
}

bool _memoryImage(Widget widget) {
  return widget is Image && widget.image is MemoryImage;
}
