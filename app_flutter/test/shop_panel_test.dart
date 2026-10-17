import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/floating_slot.dart';
import 'package:idle_kingdoms/src/ui/format.dart';
import 'package:idle_kingdoms/src/ui/item_icon.dart';
import 'package:idle_kingdoms/src/ui/shop_panel.dart';
import 'package:idle_kingdoms/src/ui/top_hud.dart';
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
    await tester.tap(find.byTooltip('Wooden axe'));
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
    final unit = playerBuyPrice(database.launch, getShop(database.launch, shopId)!, woodenAxeId)!;
    // The tile reads `price · stock left today`; the pad spells it out.
    expect(find.text('${unit}g · 1'), findsOne);
    expect(find.textContaining('left'), findsNothing);

    await tester.tap(find.byTooltip('Wooden axe'));
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

    // Tapping the offered item again opens the pad so it can be taken off.
    await tester.tap(find.byTooltip('Clay'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from offer'));
    await tester.pumpAndSettle();
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

  testWidgets('the buy pad can take an item off the offer', (tester) async {
    final controller = buildController(database, seed: shopper());
    addTearDown(controller.dispose);

    await pumpPanel(tester, ShopPanel(controller: controller, shopId: shopId));
    await tester.tap(find.byTooltip('Wooden axe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to offer'));
    await tester.pumpAndSettle();
    expect(find.text('×1'), findsOne);

    await tester.tap(find.byTooltip('Wooden axe'));
    await tester.pumpAndSettle();
    expect(find.text('Update offer'), findsOne);
    await tester.tap(find.text('Remove from offer'));
    await tester.pumpAndSettle();
    expect(find.text('×1'), findsNothing);
    expect(find.text('Confirm trade'), findsOne);
    expect(
      tester.widget<GameButton>(find.widgetWithText(GameButton, 'Confirm trade')).onPressed,
      isNull,
    );
  });

  testWidgets('unaffordable buys are greyed and cannot be offered', (tester) async {
    final controller = buildController(database, seed: shopper(gold: 0));
    addTearDown(controller.dispose);

    await pumpPanel(tester, ShopPanel(controller: controller, shopId: shopId));
    final axe = tester.widget<FloatingItemSlot>(
      find.ancestor(of: find.byTooltip('Wooden axe'), matching: find.byType(FloatingItemSlot)),
    );
    expect(axe.enabled, isFalse);
    expect(axe.onTap, isNull);

    await tester.tap(find.byTooltip('Wooden axe'));
    await tester.pumpAndSettle();
    expect(find.text('Add to offer'), findsNothing);
    expect(
      tester.widget<GameButton>(find.widgetWithText(GameButton, 'Confirm trade')).onPressed,
      isNull,
    );
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

  testWidgets('buys Leather gloves from the Clothier', (tester) async {
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
    await tester.ensureVisible(find.byTooltip('Leather gloves'));
    await tester.tap(find.byTooltip('Leather gloves'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to offer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm trade'));
    await tester.pump();

    expect(controller.save.gold, 1000 - unit);
    expect(inventoryCount(controller.save, glovesId), 1);
  });

  testWidgets('buys a Leather helmet from the Clothier', (tester) async {
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
    await tester.ensureVisible(find.byTooltip('Leather helmet'));
    await tester.tap(find.byTooltip('Leather helmet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to offer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm trade'));
    await tester.pump();

    expect(unit, 4);
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
    expect(
      tester.getTopLeft(find.text('Buy')).dy,
      lessThan(tester.getTopLeft(find.text('Sell')).dy),
    );
    final grids = tester.widgetList<GridView>(find.byType(GridView)).toList();
    expect(grids, isNotEmpty);
    expect(grids.every((grid) => grid.physics is! NeverScrollableScrollPhysics), isTrue);
  });

  testWidgets('Buy stacks above Sell at desktop and phone widths', (tester) async {
    for (final size in const [Size(900, 2400), Size(360, 740)]) {
      final controller = buildController(
        database,
        seed: shopper(inventory: [const InventoryStack(itemId: clayId, quantity: 4)]),
      );
      addTearDown(controller.dispose);
      await pumpPanel(
        tester,
        ShopPanel(controller: controller, shopId: shopId),
        size: size,
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getTopLeft(find.text('Buy')).dy,
        lessThan(tester.getTopLeft(find.text('Sell')).dy),
      );
      expect(
        tester.getCenter(find.text('Buy')).dx,
        closeTo(tester.getCenter(find.text('Sell')).dx, 1),
      );
    }
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
    expect(shop.bottom, lessThanOrEqualTo(band.top));
    await tester.ensureVisible(find.byTooltip('Clay'));
    expect(find.byTooltip('Clay').hitTestable(), findsOne);
    expect(find.text('Confirm trade').hitTestable(), findsOne);
  });

  testWidgets('HUD gold stays visible with the shop open', (tester) async {
    const gold = 7777;
    final controller = buildController(
      database,
      seed: shopper(
        gold: gold,
        inventory: [const InventoryStack(itemId: clayId, quantity: 4)],
      ),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(900, 1600));

    await selectLocationBandTab(tester, 'Shops');
    final store = find.ancestor(of: find.text('General Store'), matching: find.byType(DockRow));
    await tapVisible(tester, find.descendant(of: store, matching: find.bySemanticsLabel('Shop')));

    expect(find.byType(ShopPanel), findsOne);
    expect(find.byKey(const Key('shop-gold-balance')), findsNothing);
    expect(find.byType(GoldAmount), findsNothing);
    final hudGold = find.byKey(const Key('hud-gold'));
    expect(hudGold.hitTestable(), findsOne);
    expect(find.descendant(of: hudGold, matching: find.text(formatThousands(gold))), findsOne);
    final goldRect = tester.getRect(hudGold);
    final hud = tester.getRect(find.byType(TopHud));
    expect(goldRect.top, greaterThanOrEqualTo(hud.top));
    expect(goldRect.bottom, lessThanOrEqualTo(hud.bottom + 1));
  });

  testWidgets('offer sits on the header line and gold stays off the menu', (tester) async {
    final controller = buildController(
      database,
      seed: shopper(inventory: [const InventoryStack(itemId: clayId, quantity: 4)]),
    );
    addTearDown(controller.dispose);
    await pumpPanel(tester, ShopPanel(controller: controller, shopId: shopId, onClose: () {}));

    expect(find.byKey(const Key('shop-gold-balance')), findsNothing);
    expect(find.byType(GoldAmount), findsNothing);
    expect(find.byKey(const Key('shop-offer-summary')), findsOne);

    final offer = tester.getRect(find.byKey(const Key('shop-offer-summary')));
    final close = tester.getRect(find.byTooltip('Close'));
    final title = tester.getRect(find.text('General Store'));
    expect(offer.center.dy, closeTo(close.center.dy, 16));
    expect(title.right, lessThan(offer.left + 8));
    expect(offer.right, lessThanOrEqualTo(close.left + 8));

    final cell = tester.getRect(find.byTooltip('Clay'));
    final icon = tester.getRect(
      find.descendant(of: find.byTooltip('Clay'), matching: find.byType(ItemIcon)),
    );
    expect(icon.center.dx, closeTo(cell.center.dx, 6));
  });
}
