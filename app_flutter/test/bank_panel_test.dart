import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/bank_panel.dart';
import 'package:idle_kingdoms/src/ui/format.dart';
import 'package:idle_kingdoms/src/ui/item_icon.dart';
import 'package:idle_kingdoms/src/ui/location_view.dart';
import 'package:idle_kingdoms/src/ui/top_hud.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  const clayId = 'ITEM-0002';
  const oreId = 'ITEM-0003';

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  PlayerSave stashed({
    List<InventoryStack> inventory = const [],
    List<InventoryStack> bank = const [],
  }) {
    return startedCharacter(database).copyWith(inventory: inventory, bank: bank);
  }

  testWidgets('deposits from the bag and withdraws back', (tester) async {
    final controller = buildController(
      database,
      seed: stashed(inventory: [const InventoryStack(itemId: clayId, quantity: 5)]),
    );
    addTearDown(controller.dispose);

    await pumpPanel(tester, BankPanel(controller: controller));
    await tester.tap(find.byTooltip('Clay'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Max'));
    await tester.pump();
    await tester.tap(find.text('Deposit'));
    await tester.pumpAndSettle();

    expect(controller.save.inventory, isEmpty);
    expect(controller.save.bank.single.itemId, clayId);
    expect(controller.save.bank.single.quantity, 5);

    await tester.tap(find.byTooltip('Clay'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Max'));
    await tester.pump();
    await tester.tap(find.text('Withdraw'));
    await tester.pumpAndSettle();

    expect(controller.save.bank, isEmpty);
    expect(controller.save.inventory.single.quantity, 5);
  });

  testWidgets('filters both sides by the search field', (tester) async {
    final controller = buildController(
      database,
      seed: stashed(
        inventory: [const InventoryStack(itemId: clayId, quantity: 2)],
        bank: [const InventoryStack(itemId: oreId, quantity: 3)],
      ),
    );
    addTearDown(controller.dispose);

    await pumpPanel(tester, BankPanel(controller: controller));
    expect(find.byTooltip('Clay'), findsOne);
    expect(find.byTooltip('Copper ore'), findsOne);

    await tester.enterText(find.byType(TextField), 'copper');
    await tester.pump();

    expect(find.byTooltip('Clay'), findsNothing);
    expect(find.byTooltip('Copper ore'), findsOne);
  });

  testWidgets('Bank stacks above Bag at desktop and phone widths', (tester) async {
    for (final size in const [Size(900, 2400), Size(360, 740)]) {
      final controller = buildController(
        database,
        seed: stashed(
          inventory: [const InventoryStack(itemId: clayId, quantity: 2)],
          bank: [const InventoryStack(itemId: oreId, quantity: 3)],
        ),
      );
      addTearDown(controller.dispose);
      await pumpPanel(tester, BankPanel(controller: controller), size: size);
      expect(tester.takeException(), isNull);
      expect(find.text('Bank 1/168'), findsOne);
      expect(find.text('Bag 1/84'), findsOne);
      expect(
        tester.getTopLeft(find.text('Bank 1/168')).dy,
        lessThan(tester.getTopLeft(find.text('Bag 1/84')).dy),
      );
      expect(
        tester.getCenter(find.text('Bank 1/168')).dx,
        closeTo(tester.getCenter(find.text('Bag 1/84')).dx, 1),
      );
    }
  });

  testWidgets('groups the bag column the same way as inventory', (tester) async {
    final controller = buildController(
      database,
      seed: stashed(
        inventory: const [
          InventoryStack(itemId: 'ITEM-0128', quantity: 1),
          InventoryStack(itemId: 'ITEM-0003', quantity: 2),
        ],
      ),
    );
    addTearDown(controller.dispose);

    await pumpPanel(tester, BankPanel(controller: controller));
    final ore = tester.getRect(find.byTooltip('Copper ore'));
    final sword = tester.getRect(find.byTooltip('Iron sword'));
    expect(ore.center.dx, lessThan(sword.center.dx));
  });

  testWidgets('offers the bank at Town and hides it in the Meadow', (tester) async {
    final town = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: townBankId),
    );
    addTearDown(town.dispose);
    await pumpPanel(
      tester,
      LocationView(controller: town, multiplayer: buildMultiplayer(database), onOpenMap: () {}),
    );
    await selectLocationBandTab(tester, 'Bank');
    await tester.tap(find.widgetWithText(GameButton, 'Bank').last);
    await tester.pump();
    expect(find.text('Item storage'), findsOne);

    final meadow = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
    );
    addTearDown(meadow.dispose);
    await pumpPanel(
      tester,
      LocationView(controller: meadow, multiplayer: buildMultiplayer(database), onOpenMap: () {}),
    );
    expect(find.text('Item storage'), findsNothing);
  });

  testWidgets('HUD gold stays visible with the bank open', (tester) async {
    const gold = 7777;
    final controller = buildController(
      database,
      seed: stashed(
        inventory: [const InventoryStack(itemId: clayId, quantity: 2)],
        bank: [const InventoryStack(itemId: oreId, quantity: 3)],
      ).copyWith(currentLocationId: townBankId, gold: gold),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(900, 1600));

    await selectLocationBandTab(tester, 'Bank');
    await tester.tap(find.widgetWithText(GameButton, 'Bank').last);
    await tester.pump();

    expect(find.byType(BankPanel), findsOne);
    expect(find.byType(GoldAmount), findsNothing);
    final hudGold = find.byKey(const Key('hud-gold'));
    expect(hudGold.hitTestable(), findsOne);
    expect(find.descendant(of: hudGold, matching: find.text(formatThousands(gold))), findsOne);
    final goldRect = tester.getRect(hudGold);
    final hud = tester.getRect(find.byType(TopHud));
    expect(goldRect.top, greaterThanOrEqualTo(hud.top));
    expect(goldRect.bottom, lessThanOrEqualTo(hud.bottom + 1));
  });

  testWidgets('counts sit on Bank and Bag headers and gold stays off the menu', (tester) async {
    final controller = buildController(
      database,
      seed: stashed(
        inventory: [const InventoryStack(itemId: clayId, quantity: 2)],
        bank: [const InventoryStack(itemId: oreId, quantity: 3)],
      ),
    );
    addTearDown(controller.dispose);

    await pumpPanel(tester, BankPanel(controller: controller, onClose: () {}));
    expect(find.text(bankColumnHeading(1)), findsOne);
    expect(find.text(bagColumnHeading(1)), findsOne);
    expect(find.byType(GoldAmount), findsNothing);
    expect(find.textContaining('Bag 1/84 ·'), findsNothing);

    final search = tester.getRect(find.byKey(const Key('bank-search-field')));
    final close = tester.getRect(find.byTooltip('Close'));
    final title = tester.getRect(find.text('Bank').first);
    expect(search.center.dy, closeTo(close.center.dy, 16));
    expect(title.right, lessThan(search.left));
    expect(search.right, lessThanOrEqualTo(close.left + 8));

    final cell = tester.getRect(find.byTooltip('Clay'));
    final icon = tester.getRect(
      find.descendant(of: find.byTooltip('Clay'), matching: find.byType(ItemIcon)),
    );
    expect(icon.center.dx, closeTo(cell.center.dx, 6));
    expect(icon.center.dy, lessThan(cell.bottom));
  });
}
