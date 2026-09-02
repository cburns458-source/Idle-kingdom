import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/shop_panel.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  /// The town general store, which sells starter tools and buys most resources.
  const shopId = 'SHP-0001';
  const shopLocationId = 'LOC-0024';
  const woodenAxeId = 'ITEM-0100';
  const clayId = 'ITEM-0002';

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  PlayerSave shopper({num gold = 1000, List<InventoryStack> inventory = const []}) {
    return startedCharacter(database)
        .copyWith(currentLocationId: shopLocationId, gold: gold, inventory: inventory);
  }

  testWidgets('buys a chosen quantity for the marked price', (tester) async {
    final controller = buildController(database, seed: shopper());
    addTearDown(controller.dispose);
    final unit = playerBuyPrice(database.launch, getShop(database.launch, shopId)!, woodenAxeId)!;

    await pumpPanel(tester, ShopPanel(controller: controller, shopId: shopId));
    await tester.tap(find.byTooltip('Wooden Axe'));
    await tester.pumpAndSettle();

    // The keypad opens on 1; make it 2 and add it to the offer.
    await tester.tap(find.widgetWithText(GameButton, '2'));
    await tester.pump();
    await tester.tap(find.text('Add to offer'));
    await tester.pumpAndSettle();

    expect(find.textContaining('buy ${unit * 2}'), findsOne);
    await tester.tap(find.text('Confirm trade'));
    await tester.pump();

    expect(controller.save.gold, 1000 - unit * 2);
    expect(inventoryCount(controller.save, woodenAxeId), 2);
  });

  testWidgets('caps a buy at the shop offer daily remaining', (tester) async {
    final controller = buildController(
      database,
      seed: shopper().copyWith(
        shopPurchaseDayKey: '2026-01-01',
        shopPurchasesToday: const <String, num>{'SHP-0001:ITEM-0100': 99},
      ),
    );
    addTearDown(controller.dispose);

    await pumpPanel(tester, ShopPanel(controller: controller, shopId: shopId));
    expect(find.textContaining('1 left'), findsWidgets);

    await tester.tap(find.byTooltip('Wooden Axe'));
    await tester.pumpAndSettle();
    expect(find.textContaining("left in today's stock"), findsOne);
    await tester.tap(find.text('Add to offer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm trade'));
    await tester.pump();

    expect(inventoryCount(controller.save, woodenAxeId), 1);
    expect(controller.save.shopPurchasesToday['SHP-0001:ITEM-0100'], 100);
    expect(find.text('sold out'), findsWidgets);
    expect(find.text('Add to offer'), findsNothing);
  });

  testWidgets('sells from the bag, and a second tap withdraws the offer', (tester) async {
    final controller = buildController(
      database,
      seed: shopper(gold: 0, inventory: [const InventoryStack(itemId: clayId, quantity: 4)]),
    );
    addTearDown(controller.dispose);
    final unit = playerSellPrice(database.launch, getShop(database.launch, shopId)!, clayId)!;

    await pumpPanel(tester, ShopPanel(controller: controller, shopId: shopId));
    await tester.tap(find.byTooltip('Clay'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Max'));
    await tester.pump();
    await tester.tap(find.text('Add to offer'));
    await tester.pumpAndSettle();

    expect(find.text('×4'), findsOne);

    // Tapping the offered item again takes it back off the counter.
    await tester.tap(find.byTooltip('Clay'));
    await tester.pump();
    expect(find.text('×4'), findsNothing);

    // Put it back and go through with it.
    await tester.tap(find.byTooltip('Clay'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Max'));
    await tester.pump();
    await tester.tap(find.text('Add to offer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm trade'));
    await tester.pump();

    expect(controller.save.gold, unit * 4);
    expect(inventoryCount(controller.save, clayId), 0);
  });

  testWidgets('refuses a trade the purse cannot cover', (tester) async {
    final controller = buildController(database, seed: shopper(gold: 0));
    addTearDown(controller.dispose);

    await pumpPanel(tester, ShopPanel(controller: controller, shopId: shopId));
    await tester.tap(find.byTooltip('Wooden Axe'));
    await tester.pumpAndSettle();
    // With no gold the keypad offers no ceiling, but the trade still checks.
    await tester.tap(find.text('Add to offer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm trade'));
    await tester.pump();

    expect(find.textContaining('gold'), findsWidgets);
    expect(controller.save.gold, 0);
    expect(inventoryCount(controller.save, woodenAxeId), 0);
  });

  testWidgets('says why a shop cannot be used', (tester) async {
    // Standing somewhere else, so the counter is out of reach.
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
    );
    addTearDown(controller.dispose);

    await pumpPanel(tester, ShopPanel(controller: controller, shopId: shopId));
    expect(find.text('General Store'), findsOne);
    expect(find.text('Confirm trade'), findsNothing);
  });

  testWidgets('buys Leather Gloves from the Clothier', (tester) async {
    const clothierId = 'SHP-0006';
    const glovesId = 'ITEM-0298';
    final controller = buildController(
      database,
      seed: startedCharacter(database)
          .copyWith(currentLocationId: 'LOC-0029', gold: 1000, inventory: const []),
    );
    addTearDown(controller.dispose);
    final unit = playerBuyPrice(database.launch, getShop(database.launch, clothierId)!, glovesId)!;

    await pumpPanel(tester, ShopPanel(controller: controller, shopId: clothierId));
    await tester.ensureVisible(find.byTooltip('Leather Gloves'));
    await tester.tap(find.byTooltip('Leather Gloves'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to offer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm trade'));
    await tester.pump();

    expect(controller.save.gold, 1000 - unit);
    expect(inventoryCount(controller.save, glovesId), 1);
  });

  testWidgets('buys a Leather Helmet from the Clothier', (tester) async {
    const clothierId = 'SHP-0006';
    const helmetId = 'ITEM-0308';
    final controller = buildController(
      database,
      seed: startedCharacter(database)
          .copyWith(currentLocationId: 'LOC-0029', gold: 1000, inventory: const []),
    );
    addTearDown(controller.dispose);
    final unit = playerBuyPrice(database.launch, getShop(database.launch, clothierId)!, helmetId)!;

    await pumpPanel(tester, ShopPanel(controller: controller, shopId: clothierId));
    await tester.ensureVisible(find.byTooltip('Leather Helmet'));
    await tester.tap(find.byTooltip('Leather Helmet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to offer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm trade'));
    await tester.pump();

    expect(unit, 56);
    expect(controller.save.gold, 1000 - unit);
    expect(inventoryCount(controller.save, helmetId), 1);
  });

  testWidgets('offer chrome sits above the inventories and the grids scroll', (tester) async {
    final controller = buildController(
      database,
      seed: shopper(inventory: [const InventoryStack(itemId: clayId, quantity: 4)]),
    );
    addTearDown(controller.dispose);
    await pumpPanel(tester, ShopPanel(controller: controller, shopId: shopId));

    expect(find.text('Confirm trade').hitTestable(), findsOne);
    expect(
      tester.getTopLeft(find.textContaining('Offer —')).dy,
      lessThan(tester.getTopLeft(find.text('Buy')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Confirm trade')).dy,
      lessThan(tester.getTopLeft(find.text('Buy')).dy),
    );
    final grids = tester.widgetList<GridView>(find.byType(GridView)).toList();
    expect(grids, isNotEmpty);
    expect(grids.every((grid) => grid.physics is! NeverScrollableScrollPhysics), isTrue);
  });

  testWidgets('a phone-sized location keeps Confirm trade on screen', (tester) async {
    final controller = buildController(
      database,
      seed: shopper(inventory: [const InventoryStack(itemId: clayId, quantity: 4)]),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(375, 667));

    await tapVisible(tester, find.byTooltip('Expand list'));
    await tester.tap(find.widgetWithText(GameButton, 'Shops'));
    await tester.pump();
    final store = find.ancestor(of: find.text('General Store'), matching: find.byType(DockRow));
    await tapVisible(tester, find.descendant(of: store, matching: find.bySemanticsLabel('Shop')));

    expect(find.text('Sell'), findsOne);
    expect(find.text('Confirm trade').hitTestable(), findsOne);
    final shop = tester.getRect(find.byType(ShopPanel));
    final band = tester.getRect(find.byTooltip('Expand list'));
    expect(shop.bottom, lessThanOrEqualTo(band.top + 8));
    await tester.ensureVisible(find.byTooltip('Clay'));
    expect(find.byTooltip('Clay').hitTestable(), findsOne);
    expect(find.text('Confirm trade').hitTestable(), findsOne);
  });
}
