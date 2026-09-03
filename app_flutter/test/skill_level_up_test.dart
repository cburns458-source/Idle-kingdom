import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  testWidgets('a crafting level-up lists Leather Straps', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);
    await tester.pump();

    expect(controller.debugAddSkillLevels('SKL-0009', 9), 'Crafting is now level 10.');
    await tester.pump();
    await tester.pump();

    expect(find.text('Level 10 Crafting'), findsOne);
    expect(find.text('· Leather Straps'), findsOne);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Level 10 Crafting'), findsNothing);
  });

  testWidgets('a combat level-up does not list fight names', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);
    await tester.pump();

    expect(controller.debugAddSkillLevels(combatSkillId, 10), 'Combat is now level 11.');
    await tester.pump();
    await tester.pump();

    expect(find.text('Level 11 Combat'), findsOne);
    expect(find.textContaining('Fight '), findsNothing);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Level 11 Combat'), findsNothing);
  });

  testWidgets('a stone level-up uses panel ink instead of parchment gold', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);
    controller.setUiChromePack(UiChromePack.stone);
    await tester.pump();

    expect(controller.debugAddSkillLevels('SKL-0009', 9), 'Crafting is now level 10.');
    await tester.pump();
    await tester.pump();

    expect(find.byType(GamePanel), findsOne);
    final chrome = UiChrome.forPack(UiChromePack.stone);
    final heading = tester.widget<Text>(find.text('Level up'));
    expect(heading.style?.color, chrome.panelMuted);
    expect(heading.style?.color, isNot(Palette.muted));

    final title = tester.widget<Text>(find.text('Level 10 Crafting'));
    expect(title.style?.color, chrome.panelInk);
    expect(title.style?.color, isNot(Palette.parchmentText));

    final unlock = tester.widget<Text>(find.text('· Leather Straps'));
    expect(unlock.style?.color, chrome.embossFace);
    expect(unlock.style?.color, isNot(Palette.gold));
  });
}
