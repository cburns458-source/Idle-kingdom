import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/ui/codex_view.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  testWidgets('filters and searches the item codex', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpPanel(tester, CodexView(controller: controller));
    expect(find.text('Items'), findsOne);
    expect(find.text('Bestiary'), findsOne);
    expect(find.byKey(const Key('codex-filter-all')), findsOne);

    await tester.enterText(find.byType(TextField), 'copper ore');
    await tester.pump();
    expect(find.byKey(const Key('codex-item-ITEM-0003')), findsOne);
    expect(find.byKey(const Key('codex-item-ITEM-0128')), findsNothing);

    await tester.tap(find.byKey(const Key('codex-filter-$groupMining')));
    await tester.pump();
    expect(find.byKey(const Key('codex-item-ITEM-0003')), findsOne);
  });

  testWidgets('opens an item and follows a recipe ingredient', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpPanel(tester, CodexView(controller: controller, initialItemId: 'ITEM-0058'));
    expect(find.text('Baked Potato'), findsWidgets);
    expect(find.text('Crafted by'), findsOne);
    expect(find.byKey(const Key('codex-link-ITEM-0025')), findsOne);

    await tester.tap(find.byKey(const Key('codex-link-ITEM-0025')));
    await tester.pump();
    expect(find.text('Potato'), findsWidgets);
    expect(find.text('Used in'), findsOne);

    await tester.tap(find.text('Close'));
    await tester.pump();
    expect(find.text('Baked Potato'), findsWidgets);
  });

  testWidgets('opens a bestiary drop into the item page', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpPanel(tester, CodexView(controller: controller, initialEnemyId: 'ENM-0001'));
    expect(find.text('Cow'), findsWidgets);
    expect(find.text('The Farm'), findsWidgets);
    expect(find.text('Drops'), findsOne);

    await tester.tap(find.byKey(const Key('codex-drop-ITEM-0054')));
    await tester.pump();
    expect(find.text('Obtained from'), findsOne);
    expect(find.text('Cow'), findsWidgets);
  });
}
