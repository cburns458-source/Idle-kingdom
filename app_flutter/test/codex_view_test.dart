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
    expect(find.text('Actions'), findsOne);
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

  testWidgets('opens an item and replaces detail when following a recipe link', (tester) async {
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
    // Replace (not stack): close returns to catalog, not the previous item.
    expect(find.text('Items'), findsOne);
    expect(find.text('Actions'), findsOne);
    expect(find.text('Bestiary'), findsOne);
    expect(find.text('Used in'), findsNothing);
  });

  testWidgets('hides pets, cosmetics, and quest items from the item catalog', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpPanel(tester, CodexView(controller: controller));
    await tester.enterText(find.byType(TextField), 'fly pet');
    await tester.pump();
    expect(find.byKey(const Key('codex-item-ITEM-0320')), findsNothing);

    await tester.enterText(find.byType(TextField), "traveler's tunic");
    await tester.pump();
    expect(find.byKey(const Key('codex-item-ITEM-0296')), findsNothing);

    await tester.enterText(find.byType(TextField), 'purse');
    await tester.pump();
    expect(find.byKey(const Key('codex-item-ITEM-0299')), findsNothing);
    expect(find.text('Nothing in the Codex matches.'), findsOne);
  });

  testWidgets('opens a mining action with secondary gem drops', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpPanel(tester, CodexView(controller: controller, initialActionId: 'ACN-0018'));
    expect(find.text('Mine copper ore'), findsWidgets);
    expect(find.textContaining('Secondary'), findsOne);
    expect(find.text('Sapphire'), findsWidgets);

    await tester.tap(find.byKey(const Key('codex-action-drop-Secondary-ITEM-0012')));
    await tester.pump();
    expect(find.text('Obtained from'), findsOne);
    expect(find.byKey(const Key('codex-obtain-action-ACN-0018')), findsOne);
  });

  testWidgets('opens a bestiary drop into the item page', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpPanel(tester, CodexView(controller: controller, initialEnemyId: 'ENM-0001'));
    expect(find.text('Cow'), findsWidgets);
    expect(find.text('The Farm'), findsWidgets);
    expect(find.text('Drops'), findsOne);
    expect(find.textContaining('Drop rate'), findsWidgets);

    await tester.tap(find.byKey(const Key('codex-drop-ITEM-0054')));
    await tester.pump();
    expect(find.text('Obtained from'), findsOne);
    expect(find.text('Beef'), findsWidgets);
    expect(find.byKey(const Key('codex-obtain-enemy-ENM-0001')), findsOne);
    expect(find.text('Cow'), findsWidgets);
  });

  testWidgets('codex filter chips include Botany and Thievery', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpPanel(tester, CodexView(controller: controller));
    expect(inventoryGroupOrder, containsAll([groupBotany, groupThievery]));
    expect(inventoryGroupLabel(groupBotany), 'Botany');
    expect(inventoryGroupLabel(groupThievery), 'Thievery');
    expect(find.text('Botany'), findsNothing);
    // Chips are in a horizontal list; drag until the Botany/Thievery labels paint.
    final filterList = find.descendant(of: find.byType(CodexView), matching: find.byType(ListView));
    for (var i = 0; i < 8; i++) {
      await tester.drag(filterList.first, const Offset(-120, 0));
      await tester.pump();
      if (find.text('Botany').evaluate().isNotEmpty &&
          find.text('Thievery').evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.text('Botany'), findsWidgets);
    expect(find.text('Thievery'), findsWidgets);
  });
}
