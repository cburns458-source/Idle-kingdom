import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
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
    await tester.enterText(find.byType(TextField), 'chick pet');
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

  testWidgets('opens a mining action with gem drops kept off the ore pool', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpPanel(tester, CodexView(controller: controller, initialActionId: 'ACN-0018'));
    expect(find.text('Mine copper ore'), findsWidgets);
    expect(find.textContaining('Primary · 71.3% drop'), findsOne);
    expect(find.textContaining('Gems · 0.5% drop'), findsOne);
    expect(find.text('Copper Ore'), findsWidgets);
    expect(find.text('Sapphire'), findsWidgets);
    expect(find.textContaining('Drop rate 100%'), findsWidgets);

    await tester.tap(find.byKey(const Key('codex-action-drop-Gems-ITEM-0012')));
    await tester.pump();
    expect(find.text('Obtained from'), findsOne);
    expect(find.byKey(const Key('codex-obtain-action-ACN-0018')), findsOne);
  });

  testWidgets('opens a hunting action with primary and secondary drop tables', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpPanel(tester, CodexView(controller: controller, initialActionId: 'ACN-0014'));
    expect(find.textContaining('Primary · 63.8% drop'), findsOne);
    expect(find.textContaining('Secondary · 5% drop'), findsOne);
    expect(find.text('Venison'), findsWidgets);
    expect(find.text('Elk Hide'), findsWidgets);
    expect(find.text('Elk Horns'), findsWidgets);
    expect(find.text('Animal Tendons'), findsWidgets);
    expect(find.textContaining('Drop rate 45%'), findsOne);
    expect(find.textContaining('Drop rate 50%'), findsOne);
    expect(find.textContaining('Drop rate 5%'), findsWidgets);
    expect(find.textContaining('Drop rate 100%'), findsOne);
  });

  testWidgets('opens a bestiary drop into the item page', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpPanel(tester, CodexView(controller: controller, initialEnemyId: 'ENM-0001'));
    expect(find.text('Cow'), findsWidgets);
    expect(find.text('The Farm'), findsWidgets);
    expect(find.textContaining('Primary · 40% drop'), findsOne);
    expect(find.text('Drops'), findsNothing);
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

  testWidgets('action level and location captions use board muted ink', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final chrome in [UiChrome.wood, UiChrome.stone]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: UiChromeScope(
            chrome: chrome,
            child: Scaffold(body: CodexView(controller: controller)),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Actions'));
      await tester.pump();
      final detail = tester.widget<Text>(find.textContaining('Level 1 ·').first);
      expect(detail.style?.color, Palette.muted);
      expect(detail.style?.color, isNot(chrome.embossFace));
    }
  });

  testWidgets('groups gathering actions by skill and hides gem mining', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpPanel(tester, CodexView(controller: controller));
    await tester.tap(find.text('Actions'));
    await tester.pump();
    expect(find.text('Mining'), findsWidgets);
    expect(find.text('Mine copper ore'), findsWidgets);
    expect(find.text('Mine sapphire'), findsNothing);
    expect(find.text('Mine emerald'), findsNothing);
    expect(find.text('Mine ruby'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Woodcutting'),
      400,
      scrollable: find.descendant(
        of: find.byKey(const Key('codex-action-list')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Woodcutting'), findsWidgets);
  });

  testWidgets('fight obtain lines open the bestiary enemy', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpPanel(tester, CodexView(controller: controller, initialItemId: 'ITEM-0122'));
    expect(find.byKey(const Key('codex-obtain-enemy-ENM-0004')), findsOne);

    await tester.tap(find.byKey(const Key('codex-obtain-enemy-ENM-0004')));
    await tester.pump();
    expect(find.text('Goblin Chief'), findsWidgets);
    expect(find.textContaining('Primary · 30% drop'), findsOne);
    expect(find.textContaining('Secondary · 50% drop'), findsOne);
    expect(find.text('Goblin Staff'), findsWidgets);
    expect(find.textContaining('Drop rate 100%'), findsOne);
  });

  testWidgets('opens a placeholder bestiary enemy with derived combat level', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpPanel(tester, CodexView(controller: controller, initialEnemyId: 'ENM-0025'));
    expect(find.text('Giant Rat'), findsWidgets);
    expect(find.text('Level 8'), findsOne);
    expect(find.textContaining('Might 5'), findsOne);
    expect(find.textContaining('Vitality 5'), findsOne);
    expect(find.textContaining('Health 127'), findsOne);
    expect(find.textContaining('Damage 12–26'), findsOne);
    expect(find.textContaining('Combat XP'), findsOne);
    expect(find.text('No item drops.'), findsOne);
  });
}
