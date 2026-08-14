import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/ui/inventory_view.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  /// The starter kit with everything taken off, so the bag holds the gear.
  PlayerSave unequippedCharacter() {
    var save = startedCharacter(database);
    for (final slotId in save.equipment.slots.keys.toList()) {
      final result = unequipSlot(save, slotId);
      if (result.ok) save = result.save!;
    }
    return save;
  }

  testWidgets('equips from the bag and takes it off again', (tester) async {
    final controller = buildController(database, seed: unequippedCharacter());
    addTearDown(controller.dispose);

    // Whatever the starter kit happens to include, rather than a pinned item.
    final gear = controller.save.inventory
        .map((stack) => equipmentForItemId(database.launch, stack.itemId))
        .nonNulls
        .firstWhere((row) => row.slotId != null);
    final slotId = gear.slotId!;
    final name = database.launchIndexes.itemsById[gear.itemId]!.displayName;

    await pumpPanel(tester, InventoryView(controller: controller));
    await tester.tap(find.text(name).first);
    await tester.pump();

    expect(controller.save.equipment.slots[slotId]?.itemId, gear.itemId);

    // The paper doll shows it, and tapping it there puts it back in the bag.
    await tester.tap(find.text('Equipment'));
    await tester.pump();
    await tester.tap(find.text(name).first);
    await tester.pump();

    expect(controller.save.equipment.slots[slotId], isNull);
    expect(controller.save.inventory.any((stack) => stack.itemId == gear.itemId), isTrue);
  });

  testWidgets('sells a chosen stack for what the location pays', (tester) async {
    final seed = unequippedCharacter().copyWith(
      inventory: [const InventoryStack(itemId: 'ITEM-0002', quantity: 5)],
      gold: 0,
    );
    final controller = buildController(database, seed: seed);
    addTearDown(controller.dispose);
    final unitPrice = sellPriceAtLocation(database.launch, controller.save, 'ITEM-0002')!.unitPrice;

    await pumpPanel(tester, InventoryView(controller: controller));
    await tester.tap(find.text('Sell items'));
    await tester.pump();
    await tester.tap(find.text('Clay').first);
    await tester.pump();

    expect(find.textContaining('Sell selected'), findsOne);
    await tester.tap(find.textContaining('Sell selected'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm sell'));
    await tester.pumpAndSettle();

    expect(controller.save.gold, unitPrice * 5);
    expect(controller.save.inventory, isEmpty);
  });

  testWidgets('refuses to sell a favorited stack', (tester) async {
    final seed = unequippedCharacter().copyWith(
      inventory: [const InventoryStack(itemId: 'ITEM-0002', quantity: 5, favorite: true)],
    );
    final controller = buildController(database, seed: seed);
    addTearDown(controller.dispose);

    await pumpPanel(tester, InventoryView(controller: controller));
    await tester.tap(find.text('Sell items'));
    await tester.pump();
    await tester.tap(find.text('Clay').first);
    await tester.pump();

    expect(find.text('Favorited items cannot be sold. Unfavorite them first.'), findsOne);
    // Nothing was selected, so there is nothing to confirm.
    expect(find.text('Sell selected'), findsOne);
  });

  testWidgets('the detail sheet reports what an item is worth', (tester) async {
    final seed = unequippedCharacter().copyWith(
      inventory: [const InventoryStack(itemId: 'ITEM-0002', quantity: 5)],
    );
    final controller = buildController(database, seed: seed);
    addTearDown(controller.dispose);

    await pumpPanel(tester, InventoryView(controller: controller));
    await tester.longPress(find.text('Clay').first);
    await tester.pumpAndSettle();

    expect(find.text('×5'), findsOne);
    expect(find.textContaining('value each'), findsOne);
  });

  testWidgets('combat stats live on the equipment page, not the bag', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpPanel(tester, InventoryView(controller: controller));
    expect(find.text('Damage'), findsNothing);
    expect(find.text('Show sources'), findsNothing);

    await tester.tap(find.text('Equipment'));
    await tester.pump();

    expect(find.text('Damage'), findsOne);
    expect(find.text('Health'), findsOne);
    expect(find.text('DR'), findsOne);
    expect(find.text('No active bonuses.'), findsOne);

    await tester.tap(find.text('Show sources'));
    await tester.pump();
    expect(find.text('Hide sources'), findsOne);
    expect(find.text('Main-hand'), findsOne);
    expect(find.text('Unarmed'), findsOne);
    expect(find.text('Damage reduction'), findsOne);
    expect(find.text('Total'), findsWidgets);
  });

  testWidgets('equipment page lists potion and race bonuses', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(
        raceId: 'RACE-0003',
        activePotionEffect: const ActivePotionEffect(
          scope: 'one_combat_encounter',
          itemId: 'ITEM-0072',
          damageBonusPercent: 10,
        ),
      ),
    );
    addTearDown(controller.dispose);

    await pumpPanel(tester, InventoryView(controller: controller));
    await tester.tap(find.text('Equipment'));
    await tester.pump();

    expect(find.text('No active bonuses.'), findsNothing);
    expect(find.textContaining('High Elf'), findsOne);
    expect(find.textContaining('Strength Potion'), findsOne);
  });

  testWidgets('the favorite heart sits at the top-right of an item tile', (tester) async {
    final seed = unequippedCharacter().copyWith(
      inventory: [
        const InventoryStack(
          itemId: 'ITEM-0002',
          quantity: 1,
          enchantmentId: 'ENCH-0003',
          favorite: true,
        ),
      ],
    );
    final controller = buildController(database, seed: seed);
    addTearDown(controller.dispose);

    await pumpPanel(tester, InventoryView(controller: controller));

    final tile = tester.getRect(
      find.ancestor(of: find.text('Clay'), matching: find.byType(InkWell)),
    );
    final heart = tester.getRect(find.byTooltip('Unfavorite'));
    expect(heart.right, closeTo(tile.right, 12));
    expect(heart.top, closeTo(tile.top, 12));

    final star = tester.getRect(find.text('★'));
    expect(star.right, lessThanOrEqualTo(heart.right));
    expect(star.top, closeTo(tile.top, 12));
  });
}
