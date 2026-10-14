import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/bank_panel.dart';
import 'package:idle_kingdoms/src/ui/floating_slot.dart';
import 'package:idle_kingdoms/src/ui/format.dart';
import 'package:idle_kingdoms/src/ui/inventory_view.dart';
import 'package:idle_kingdoms/src/ui/item_icon.dart';
import 'package:idle_kingdoms/src/ui/item_label.dart';
import 'package:idle_kingdoms/src/ui/shop_panel.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  const copperAxeId = 'ITEM-0132';
  const clayId = 'ITEM-0002';
  const essenceId = 'ITEM-0011';
  const enchantmentId = 'ENCH-0001';
  const copperAxe = 'Copper Axe';
  const enchantment = 'Item Enchantment';
  const enchantedAxeTooltip = '$copperAxe\n$enchantment';
  const enchantedAxeLabel = '$copperAxe • $enchantment';

  /// The town General Store buys plain gear and enchanted gear alike.
  const generalStoreId = 'SHP-0001';
  const generalStoreLocationId = 'LOC-0024';

  /// The Wizard's Shop only buys enchanted gear, so every Sell tile is enchanted.
  const wizardsShopId = 'SHP-0003';
  const wizardsTowerId = 'LOC-0007';

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  PlayerSave unequippedCharacter() {
    var save = startedCharacter(database);
    for (final slotId in save.equipment.slots.keys.toList()) {
      final result = unequipSlot(save, slotId);
      if (result.ok) save = result.save!;
    }
    return save;
  }

  const enchantedAxe = InventoryStack(
    itemId: copperAxeId,
    quantity: 1,
    enchantmentId: enchantmentId,
  );
  const plainAxe = InventoryStack(itemId: copperAxeId, quantity: 1);

  /// Every tile cell on screen, as the rectangle a finger has to land in.
  List<Rect> tileRects(WidgetTester tester) => [
    for (final element in find.byType(FloatingItemSlot).evaluate())
      tester.getRect(find.byWidget(element.widget)),
  ];

  group('item labels', () {
    test('name the enchantment only when there is one', () {
      expect(enchantmentName(database.launch, enchantmentId), enchantment);
      expect(enchantmentName(database.launch, null), isNull);
      expect(enchantmentName(database.launch, ''), isNull);
      expect(enchantmentName(database.launch, 'ENCH-9999'), 'Enchanted (ENCH-9999)');

      expect(itemTileTooltip(copperAxe, enchantment), enchantedAxeTooltip);
      expect(itemTileTooltip(copperAxe, null), copperAxe);
      expect(enchantedItemLabel(copperAxe, enchantment), enchantedAxeLabel);
      expect(enchantedItemLabel(copperAxe, null), copperAxe);
    });

    test('dense grid columns land near the tile size and never under 48px', () {
      double cell(double width) {
        final columns = denseGridColumns(width, tile: shopTileExtent, gap: shopTileGap);
        return (width - (columns - 1) * shopTileGap) / columns;
      }

      for (var width = 48.0; width <= 900; width += 1) {
        expect(cell(width), greaterThanOrEqualTo(minItemTapExtent), reason: 'width $width');
      }
      // Wide enough for three 60px cells: three it is, not four 45px ones.
      expect(denseGridColumns(192, tile: shopTileExtent, gap: shopTileGap), 3);
      expect(denseGridColumns(193, tile: shopTileExtent, gap: shopTileGap), 3);
      expect(cell(250), closeTo(59.5, 0.1));
      // The playable column's half width: three ~49px cells sit nearer 60 than
      // two 75px ones, and still clear the tap-target floor.
      expect(denseGridColumns(154, tile: shopTileExtent, gap: shopTileGap), 3);
      expect(cell(154), closeTo(48.7, 0.1));
      expect(denseGridColumns(140, tile: shopTileExtent, gap: shopTileGap), 2);
      expect(denseGridColumns(0, tile: shopTileExtent, gap: shopTileGap), 1);
      expect(denseGridColumns(20, tile: shopTileExtent, gap: shopTileGap), 1);
    });
  });

  group('bag and paper doll', () {
    testWidgets('an enchanted bag tile names its enchantment; a plain one does not', (
      tester,
    ) async {
      final controller = buildController(
        database,
        seed: unequippedCharacter().copyWith(inventory: const [enchantedAxe, plainAxe]),
      );
      addTearDown(controller.dispose);

      await pumpPanel(tester, InventoryView(controller: controller));

      expect(find.byTooltip(enchantedAxeTooltip), findsOne);
      expect(find.byTooltip(copperAxe), findsOne);
      expect(find.text('★'), findsOne);

      // Holding the enchanted tile opens the sheet, which spells the enchantment out.
      await tester.longPress(find.byTooltip(enchantedAxeTooltip));
      await tester.pumpAndSettle();
      final popup = find.byKey(const Key('game-popup'));
      expect(find.descendant(of: popup, matching: find.text(enchantment)), findsOne);
      expect(
        find.descendant(of: popup, matching: find.text('Project-defined magical property')),
        findsOne,
      );
      await tester.tap(find.descendant(of: popup, matching: find.byTooltip('Close')));
      await tester.pumpAndSettle();

      // The plain tile's sheet has no enchantment line at all.
      await tester.longPress(find.byTooltip(copperAxe));
      await tester.pumpAndSettle();
      expect(find.text(enchantment), findsNothing);
    });

    testWidgets('sell mode keeps the enchantment on the tile', (tester) async {
      final controller = buildController(
        database,
        seed: unequippedCharacter().copyWith(inventory: const [enchantedAxe, plainAxe]),
      );
      addTearDown(controller.dispose);

      await pumpPanel(tester, InventoryView(controller: controller));
      await tester.tap(find.text('Sell items'));
      await tester.pump();

      expect(find.byTooltip(enchantedAxeTooltip), findsOne);
      expect(find.byTooltip(copperAxe), findsOne);
      await tester.longPress(find.byTooltip(enchantedAxeTooltip));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byKey(const Key('game-popup')), matching: find.text(enchantment)),
        findsOne,
      );
    });

    testWidgets('a worn enchanted piece names its enchantment on the doll', (tester) async {
      final controller = buildController(
        database,
        seed: unequippedCharacter().copyWith(inventory: const [enchantedAxe]),
      );
      addTearDown(controller.dispose);

      await pumpPanel(tester, InventoryView(controller: controller));
      await tester.tap(find.byTooltip(enchantedAxeTooltip));
      await tester.pump();
      expect(controller.save.equipment.slots[weaponToolSlotId]?.enchantmentId, enchantmentId);

      final slot = find.byKey(const Key('equipment-slot-$weaponToolSlotId'));
      expect(find.descendant(of: slot, matching: find.byTooltip(enchantedAxeTooltip)), findsOne);
      expect(find.descendant(of: slot, matching: find.text('★')), findsOne);

      await tester.longPress(find.descendant(of: slot, matching: find.byType(ItemIcon)));
      await tester.pumpAndSettle();
      final popup = find.byKey(const Key('game-popup'));
      expect(find.descendant(of: popup, matching: find.text(enchantment)), findsOne);
      expect(find.descendant(of: popup, matching: find.text('Equip')), findsNothing);
    });

    testWidgets('a worn plain piece adds no enchantment line', (tester) async {
      final controller = buildController(
        database,
        seed: unequippedCharacter().copyWith(inventory: const [plainAxe]),
      );
      addTearDown(controller.dispose);

      await pumpPanel(tester, InventoryView(controller: controller));
      await tester.tap(find.byTooltip(copperAxe));
      await tester.pump();

      final slot = find.byKey(const Key('equipment-slot-$weaponToolSlotId'));
      expect(find.descendant(of: slot, matching: find.byTooltip(copperAxe)), findsOne);
      expect(find.descendant(of: slot, matching: find.text('★')), findsNothing);
    });
  });

  group('bank', () {
    testWidgets('an enchanted chest tile shows its enchantment on hold and on tap', (tester) async {
      final controller = buildController(
        database,
        seed: startedCharacter(database).copyWith(
          inventory: const [InventoryStack(itemId: clayId, quantity: 3)],
          bank: const [enchantedAxe],
        ),
      );
      addTearDown(controller.dispose);

      await pumpPanel(tester, BankPanel(controller: controller));

      final chestTile = find.byKey(const ValueKey('bank-0'));
      expect(find.descendant(of: chestTile, matching: find.text('★')), findsOne);
      expect(find.byTooltip(enchantedAxeTooltip), findsOne);
      expect(find.byTooltip('Clay'), findsOne);
      expect(find.text(enchantedAxeTooltip), findsNothing);

      await tester.longPress(chestTile);
      await tester.pump();
      expect(find.text(enchantedAxeTooltip), findsOne);
      await tester.pumpAndSettle();

      await tester.tap(chestTile);
      await tester.pumpAndSettle();
      expect(find.text(enchantedAxeLabel), findsOne);
      expect(find.text('From the chest'), findsOne);
      await tester.tap(find.text('Max'));
      await tester.pump();
      await tester.tap(find.text('Withdraw'));
      await tester.pumpAndSettle();
      expect(controller.save.inventory.last.enchantmentId, enchantmentId);
      expect(controller.save.bank, isEmpty);
    });

    testWidgets('a plain tile adds no extra line and no star', (tester) async {
      final controller = buildController(
        database,
        seed: startedCharacter(database).copyWith(
          inventory: const [InventoryStack(itemId: clayId, quantity: 3)],
          bank: const [plainAxe],
        ),
      );
      addTearDown(controller.dispose);

      await pumpPanel(tester, BankPanel(controller: controller));
      expect(find.text('★'), findsNothing);
      expect(find.byTooltip(copperAxe), findsOne);

      await tester.longPress(find.byKey(const ValueKey('bank-0')));
      await tester.pump();
      expect(find.text(copperAxe), findsOne);
      expect(find.textContaining('\n'), findsNothing);
      expect(find.textContaining('•'), findsNothing);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('bag-0')));
      await tester.pumpAndSettle();
      expect(find.text('Clay'), findsOne);
      expect(find.textContaining('•'), findsNothing);
    });
  });

  group('shop', () {
    testWidgets('a Wizard\'s Shop sell tile shows the enchantment; stock stays plain', (
      tester,
    ) async {
      final controller = buildController(
        database,
        seed: startedCharacter(
          database,
        ).copyWith(currentLocationId: wizardsTowerId, gold: 1000, inventory: const [enchantedAxe]),
      );
      addTearDown(controller.dispose);
      final shop = getShop(database.launch, wizardsShopId)!;
      final unit = playerSellPrice(database.launch, shop, copperAxeId, enchanted: true)!;

      await pumpPanel(tester, ShopPanel(controller: controller, shopId: wizardsShopId));

      // The tile tooltip carries the enchantment on its own line, with a star mark.
      expect(find.byTooltip(enchantedAxeTooltip), findsOne);
      expect(find.text('★'), findsOne);
      expect(find.text('${formatThousands(unit)}g · 1'), findsOne);
      await tester.longPress(find.byTooltip(enchantedAxeTooltip));
      await tester.pump();
      expect(find.text(enchantedAxeTooltip), findsOne);
      await tester.pumpAndSettle();

      // The quantity pad names it `Item • Enchantment`.
      await tester.tap(find.byTooltip(enchantedAxeTooltip));
      await tester.pumpAndSettle();
      expect(find.text(enchantedAxeLabel), findsOne);
      await tester.tap(find.text('Add to offer'));
      await tester.pumpAndSettle();

      // Shop stock has no enchantment, so the Buy side keeps the bare name.
      expect(find.byTooltip('Essence'), findsOne);
      await tester.tap(find.byTooltip('Essence'));
      await tester.pumpAndSettle();
      expect(find.text('Essence'), findsOne);
      expect(find.textContaining('•'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirm trade'));
      await tester.pump();
      expect(inventoryCount(controller.save, copperAxeId), 0);
      expect(inventoryCount(controller.save, essenceId), 0);
      expect(controller.save.gold, 1000 + unit);
    });

    testWidgets('a general store tile pooling plain and enchanted copies stays plain', (
      tester,
    ) async {
      final controller = buildController(
        database,
        seed: startedCharacter(database).copyWith(
          currentLocationId: generalStoreLocationId,
          inventory: const [plainAxe, enchantedAxe],
        ),
      );
      addTearDown(controller.dispose);

      await pumpPanel(tester, ShopPanel(controller: controller, shopId: generalStoreId));

      final sellSide = find.ancestor(of: find.text('Sell'), matching: find.byType(Column)).first;
      expect(find.descendant(of: sellSide, matching: find.byTooltip(copperAxe)), findsOne);
      expect(find.byTooltip(enchantedAxeTooltip), findsNothing);
      expect(find.descendant(of: sellSide, matching: find.text('★')), findsNothing);
    });

    testWidgets('only enchanted copies at a general store name the enchantment', (tester) async {
      final controller = buildController(
        database,
        seed: startedCharacter(database)
            .copyWith(currentLocationId: generalStoreLocationId, inventory: const [enchantedAxe]),
      );
      addTearDown(controller.dispose);

      await pumpPanel(tester, ShopPanel(controller: controller, shopId: generalStoreId));
      expect(find.byTooltip(enchantedAxeTooltip), findsOne);
      await tester.tap(find.byTooltip(enchantedAxeTooltip));
      await tester.pumpAndSettle();
      expect(find.text(enchantedAxeLabel), findsOne);
    });

    testWidgets('shop grids pack cells about 60px wide with a 4px gap', (tester) async {
      final controller = buildController(
        database,
        seed: startedCharacter(database).copyWith(
          currentLocationId: generalStoreLocationId,
          inventory: [
            for (var i = 0; i < 12; i += 1) const InventoryStack(itemId: clayId, quantity: 1),
          ],
        ),
      );
      addTearDown(controller.dispose);

      await pumpPanel(tester, ShopPanel(controller: controller, shopId: generalStoreId));

      final rects = tileRects(tester);
      expect(rects.length, greaterThan(4));
      for (final rect in rects) {
        expect(rect.width, inInclusiveRange(minItemTapExtent, shopTileExtent + 6));
        expect(rect.height, closeTo(rect.width, 0.5));
      }
      final buyRow = rects.where((rect) => (rect.top - rects.first.top).abs() < 1).toList()
        ..sort((a, b) => a.left.compareTo(b.left));
      expect(buyRow.length, greaterThan(1));
      expect(buyRow[1].left - buyRow[0].right, closeTo(shopTileGap, 0.5));

      final grid = tester.widget<GridView>(find.byType(GridView).first);
      final delegate = grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.mainAxisSpacing, shopTileGap);
      expect(delegate.crossAxisSpacing, shopTileGap);
    });
  });

  group('a 360px phone', () {
    const phone = Size(360, 740);

    testWidgets('shop tiles stay at least 48px and nothing overflows', (tester) async {
      final controller = buildController(
        database,
        seed: startedCharacter(database).copyWith(
          currentLocationId: generalStoreLocationId,
          gold: 1000,
          inventory: [
            for (var i = 0; i < 20; i += 1) const InventoryStack(itemId: clayId, quantity: 1),
          ],
        ),
      );
      addTearDown(controller.dispose);
      await pumpShell(tester, controller, size: phone);

      await tapVisible(tester, find.byTooltip('Expand list'));
      await tester.tap(find.widgetWithText(GameButton, 'Shops'));
      await tester.pump();
      final store = find.ancestor(of: find.text('General Store'), matching: find.byType(DockRow));
      await tapVisible(tester, find.descendant(of: store, matching: find.bySemanticsLabel('Shop')));

      expect(find.byType(ShopPanel), findsOne);
      expect(tester.takeException(), isNull);
      final rects = tileRects(tester);
      expect(rects, isNotEmpty);
      for (final rect in rects) {
        expect(rect.width, greaterThanOrEqualTo(minItemTapExtent));
        expect(rect.height, greaterThanOrEqualTo(minItemTapExtent));
      }
    });

    testWidgets('an 84-slot bag lays out without overflowing', (tester) async {
      final controller = buildController(
        database,
        seed: unequippedCharacter().copyWith(
          inventory: [
            for (var i = 0; i < inventorySlotLimit; i += 1)
              InventoryStack(itemId: clayId, quantity: i + 1),
          ],
        ),
      );
      addTearDown(controller.dispose);
      expect(inventorySlotCount(controller.save), inventorySlotLimit);
      await pumpShell(tester, controller, size: phone);

      await openChinInventory(tester);
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const Key('inventory-bag')), findsOne);
      expect(find.text('$inventorySlotLimit / $inventorySlotLimit slots'), findsOne);
      expect(tester.takeException(), isNull);
      final rects = tileRects(tester);
      expect(rects, isNotEmpty);
      for (final rect in rects) {
        expect(rect.width, greaterThanOrEqualTo(minItemTapExtent));
        expect(rect.height, greaterThanOrEqualTo(minItemTapExtent));
      }

      // Scroll to the far end so every tile has been laid out at least once.
      final bag = find.byKey(const Key('inventory-bag'));
      await tester.fling(bag, const Offset(0, -3000), 4000);
      for (var i = 0; i < 10; i += 1) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a 168-slot bank lays out without overflowing', (tester) async {
      final controller = buildController(
        database,
        seed: startedCharacter(database).copyWith(
          currentLocationId: townBankId,
          inventory: [
            for (var i = 0; i < inventorySlotLimit; i += 1)
              InventoryStack(itemId: clayId, quantity: i + 1),
          ],
          bank: [
            for (var i = 0; i < bankSlotLimit; i += 1)
              InventoryStack(itemId: clayId, quantity: i + 1),
          ],
        ),
      );
      addTearDown(controller.dispose);
      await pumpPanel(tester, BankPanel(controller: controller), size: phone);

      expect(
        find.text(
          'Bag $inventorySlotLimit/$inventorySlotLimit · Bank $bankSlotLimit/$bankSlotLimit',
        ),
        findsOne,
      );
      expect(tester.takeException(), isNull);
      final rects = tileRects(tester);
      expect(rects, isNotEmpty);
      for (final rect in rects) {
        expect(rect.width, greaterThanOrEqualTo(minItemTapExtent));
        expect(rect.height, greaterThanOrEqualTo(minItemTapExtent));
      }

      await tester.fling(find.byType(GridView).first, const Offset(0, -6000), 4000);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
