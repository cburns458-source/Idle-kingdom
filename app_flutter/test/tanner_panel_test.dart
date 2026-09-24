import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/tanner_panel.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  NpcRow npcOf(String npcId) {
    return database.launch.npcs.firstWhere((row) => row.raw['NPC ID'] == npcId);
  }

  testWidgets('the tanner shop uses a pin pad and lists leather/gold totals', (tester) async {
    var closed = 0;
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(
        currentLocationId: 'LOC-0025',
        gold: 100,
        inventory: const [
          InventoryStack(itemId: 'ITEM-0378', quantity: 2),
          InventoryStack(itemId: 'ITEM-0196', quantity: 1),
        ],
      ),
    );
    addTearDown(controller.dispose);

    await pumpPanel(
      tester,
      TannerPanel(controller: controller, npc: npcOf('NPC-0018'), onClose: () => closed += 1),
    );
    expect(find.text('Tanner'), findsOne);
    expect(find.textContaining('Offer — 0 leather / 0 gold'), findsOne);

    await tester.tap(find.byTooltip('Cowhide'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(GameButton, '2'));
    await tester.pump();
    await tester.tap(find.text('Add to offer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Offer — 6 leather / 12 gold'), findsOne);

    await tester.tap(find.byTooltip('Goat Hide'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to offer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Offer — 8 leather / 16 gold'), findsOne);

    await tester.tap(find.text('Confirm tan'));
    await tester.pump();
    expect(controller.save.gold, 84);
    expect(
      controller.save.inventory.where((stack) => stack.itemId == 'ITEM-0045').single.quantity,
      8,
    );
    expect(controller.save.inventory.any((stack) => stack.itemId == 'ITEM-0378'), isFalse);
    expect(find.textContaining('Offer — 0 leather / 0 gold'), findsOne);
    expect(closed, 0);
  });
}
