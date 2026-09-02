import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
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
    await tester.tap(find.byTooltip(name).first);
    await tester.pump();

    expect(controller.save.equipment.slots[slotId]?.itemId, gear.itemId);

    // The paper doll shows it, and tapping it there puts it back in the bag.
    await tester.tap(find.text('Equipment'));
    await tester.pump();
    await tester.tap(find.byTooltip(name).first);
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
    await tester.tap(find.byTooltip('Clay').first);
    await tester.pumpAndSettle();
    // Each stack asks for a quantity before it joins the selection.
    expect(find.text('Sell Clay'), findsOne);
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();

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
    await tester.tap(find.byTooltip('Clay').first);
    await tester.pump();

    expect(find.text('Favorited items cannot be sold. Unfavorite them first.'), findsOne);
    // Nothing was selected, so there is nothing to confirm.
    expect(find.text('Sell selected'), findsOne);
  });

  testWidgets('the detail sheet equips gear from the bag', (tester) async {
    final controller = buildController(database, seed: unequippedCharacter());
    addTearDown(controller.dispose);

    final gear = controller.save.inventory
        .map((stack) => equipmentForItemId(database.launch, stack.itemId))
        .nonNulls
        .firstWhere((row) => row.slotId != null);
    final slotId = gear.slotId!;
    final name = database.launchIndexes.itemsById[gear.itemId]!.displayName;

    await pumpPanel(tester, InventoryView(controller: controller));
    await tester.longPress(find.byTooltip(name).first);
    await tester.pumpAndSettle();

    expect(find.text('Equip'), findsOne);
    await tester.tap(find.text('Equip'));
    await tester.pumpAndSettle();

    expect(controller.save.equipment.slots[slotId]?.itemId, gear.itemId);
    expect(find.text('Equip'), findsNothing);
  });

  testWidgets('the detail sheet names a tool skill bonus and equips it', (tester) async {
    final seed = unequippedCharacter().copyWith(
      inventory: [const InventoryStack(itemId: 'ITEM-0110', quantity: 1)],
    );
    final controller = buildController(database, seed: seed);
    addTearDown(controller.dispose);

    await pumpPanel(tester, InventoryView(controller: controller));
    await tester.longPress(find.byTooltip('Copper Hatchet'));
    await tester.pumpAndSettle();

    expect(find.text('Woodcutting: -3% action time'), findsOne);
    expect(find.text('Equip'), findsOne);
    await tester.tap(find.text('Equip'));
    await tester.pumpAndSettle();
    expect(controller.save.equipment.slots[weaponToolSlotId]?.itemId, 'ITEM-0110');

    await tester.tap(find.text('Equipment'));
    await tester.pump();
    await tester.longPress(find.byTooltip('Copper Hatchet').first);
    await tester.pumpAndSettle();
    expect(find.text('Woodcutting: -3% action time'), findsOne);
    expect(find.text('Equip'), findsNothing);
  });

  testWidgets('the detail sheet reports what an item is worth', (tester) async {
    final seed = unequippedCharacter().copyWith(
      inventory: [const InventoryStack(itemId: 'ITEM-0002', quantity: 5)],
    );
    final controller = buildController(database, seed: seed);
    addTearDown(controller.dispose);

    await pumpPanel(tester, InventoryView(controller: controller));
    await tester.longPress(find.byTooltip('Clay'));
    await tester.pumpAndSettle();

    expect(find.text('×5'), findsOne);
    expect(find.textContaining('value each'), findsOne);
  });

  testWidgets('a locked equipment pane shows the paper doll, not the bag', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpPanel(
      tester,
      InventoryView(controller: controller, pane: InventoryPane.equipment, showHeader: false),
    );

    expect(find.text('Sell items'), findsNothing);
    expect(find.textContaining('slots'), findsNothing);
    expect(find.text('Damage'), findsOne);
    expect(find.text('Helmet'), findsOne);
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
    expect(find.text('Show bonuses'), findsOne);
    expect(find.text('Show sources'), findsOne);
    expect(find.textContaining('Eat at'), findsOne);
    final bonuses = tester.getRect(find.text('Show bonuses'));
    final sources = tester.getRect(find.text('Show sources'));
    expect((bonuses.center.dy - sources.center.dy).abs(), lessThan(8));
    expect(bonuses.right, lessThan(sources.left));
    expect(find.textContaining('Human'), findsNothing);

    await tester.tap(find.text('Show bonuses'));
    await tester.pump();
    expect(find.textContaining('Human'), findsWidgets);

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

    expect(find.textContaining('High Elf'), findsNothing);
    await tester.tap(find.text('Show bonuses'));
    await tester.pump();

    expect(find.text('No active bonuses.'), findsNothing);
    expect(find.textContaining('High Elf'), findsOne);
    expect(find.textContaining('Strength Potion'), findsOne);
  });

  testWidgets('equipment page lists action time reduction on the tool skill', (tester) async {
    final base = startedCharacter(database);
    final controller = buildController(
      database,
      seed: equipStackToSlot(base, weaponToolSlotId, 'ITEM-0110', 1),
    );
    addTearDown(controller.dispose);

    await pumpPanel(tester, InventoryView(controller: controller));
    await tester.tap(find.text('Equipment'));
    await tester.pump();

    expect(find.textContaining('action time'), findsNothing);
    await tester.tap(find.text('Show bonuses'));
    await tester.pump();

    expect(find.textContaining('Woodcutting'), findsWidgets);
    expect(find.textContaining('-3% action time'), findsOne);
  });

  List<String> visibleBagOrder(WidgetTester tester, List<String> names) {
    final placed =
        [for (final name in names) (name: name, rect: tester.getRect(find.byTooltip(name)))]
          ..sort((a, b) {
            if ((a.rect.center.dy - b.rect.center.dy).abs() > 12) {
              return a.rect.center.dy.compareTo(b.rect.center.dy);
            }
            return a.rect.center.dx.compareTo(b.rect.center.dx);
          });
    return [for (final entry in placed) entry.name];
  }

  testWidgets('groups the bag and only shows Search after it is picked', (tester) async {
    final seed = unequippedCharacter().copyWith(
      inventory: const [
        InventoryStack(itemId: 'ITEM-0128', quantity: 1),
        InventoryStack(itemId: 'ITEM-0003', quantity: 1),
        InventoryStack(itemId: 'ITEM-0074', quantity: 1),
        InventoryStack(itemId: 'ITEM-0058', quantity: 1, favorite: true),
        InventoryStack(itemId: 'ITEM-0025', quantity: 1),
      ],
    );
    final controller = buildController(database, seed: seed);
    addTearDown(controller.dispose);

    await pumpPanel(tester, InventoryView(controller: controller));
    expect(find.text('Sell items'), findsOne);
    expect(find.byTooltip('Sort'), findsOne);
    expect(find.byType(TextField), findsNothing);

    expect(
      visibleBagOrder(tester, ['Baked Potato', 'Copper Ore', 'Copper Bar', 'Iron Sword', 'Potato']),
      ['Baked Potato', 'Copper Ore', 'Copper Bar', 'Iron Sword', 'Potato'],
    );

    await tester.tap(find.byTooltip('Sort'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<InventorySortMode>, 'A–Z'));
    await tester.pumpAndSettle();
    expect(
      visibleBagOrder(tester, ['Baked Potato', 'Copper Bar', 'Copper Ore', 'Iron Sword', 'Potato']),
      ['Baked Potato', 'Copper Bar', 'Copper Ore', 'Iron Sword', 'Potato'],
    );

    await tester.tap(find.byTooltip('Sort'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<InventorySortMode>, 'Search'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOne);

    await tester.enterText(find.byType(TextField), 'copper');
    await tester.pump();
    expect(find.byTooltip('Copper Ore'), findsOne);
    expect(find.byTooltip('Copper Bar'), findsOne);
    expect(find.byTooltip('Potato'), findsNothing);
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

    final tile = tester.getRect(find.byTooltip('Clay'));
    final heart = tester.getRect(find.byTooltip('Unfavorite'));
    expect(heart.right, closeTo(tile.right, 12));
    expect(heart.top, closeTo(tile.top, 12));

    final star = tester.getRect(find.text('★'));
    expect(star.right, lessThanOrEqualTo(heart.right));
    expect(star.top, closeTo(tile.top, 12));
  });

  testWidgets('food tiles do not say Eat; the detail sheet still does', (tester) async {
    final seed = unequippedCharacter().copyWith(
      inventory: [const InventoryStack(itemId: 'ITEM-0028', quantity: 2)],
    );
    final controller = buildController(database, seed: seed);
    addTearDown(controller.dispose);

    await pumpPanel(tester, InventoryView(controller: controller));
    expect(find.text('Eat'), findsNothing);

    await tester.longPress(find.byTooltip('Wild berries').first);
    await tester.pumpAndSettle();
    expect(find.text('Eat'), findsOne);
  });

  testWidgets('equipping while a preset is selected edits current loadout only', (tester) async {
    var save = unequippedCharacter();
    save = addItemToInventory(save, 'ITEM-0111', 1);
    save = addItemToInventory(save, 'ITEM-0110', 1);
    final equipped = equipItemFromInventory(database.launch, save, 'ITEM-0111');
    expect(equipped.ok, isTrue);
    save = saveActiveEquipmentPreset(equipped.save!);

    final controller = buildController(database, seed: save);
    addTearDown(controller.dispose);

    await pumpPanel(tester, InventoryView(controller: controller));
    await tester.tap(find.text('Equipment'));
    await tester.pump();

    expect(find.text('Current'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Done'), findsNothing);

    await tester.tap(find.text('Current'));
    await tester.pump();
    await tester.tap(find.text('Items'));
    await tester.pump();
    await tester.tap(find.byTooltip('Copper Hatchet').first);
    await tester.pump();

    expect(controller.save.equipment.slots['SLOT-0001']?.itemId, 'ITEM-0110');
    expect(controller.save.equipmentPresets[0].slots['SLOT-0001']?.itemId, 'ITEM-0111');

    await tester.tap(find.text('Equipment'));
    await tester.pump();
    await tester.tap(find.text('I'));
    await tester.pump();
    expect(controller.save.activeEquipmentPresetIndex, 0);
    expect(controller.save.equipment.slots['SLOT-0001']?.itemId, 'ITEM-0111');

    await tester.tap(find.text('Items'));
    await tester.pump();
    await tester.tap(find.byTooltip('Copper Hatchet').first);
    await tester.pump();

    expect(controller.save.equipmentPresets[0].slots['SLOT-0001']?.itemId, 'ITEM-0111');
    expect(controller.save.equipment.slots['SLOT-0001']?.itemId, 'ITEM-0110');

    await tester.tap(find.text('Equipment'));
    await tester.pump();
    await tester.tap(find.text('I'));
    await tester.pump();
    expect(controller.save.equipment.slots['SLOT-0001']?.itemId, 'ITEM-0111');
  });

  testWidgets('opens preset settings for all four presets from equipment bar', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpPanel(tester, InventoryView(controller: controller));
    await tester.tap(find.text('Equipment'));
    await tester.pump();

    await tester.tap(find.byTooltip('Preset settings'));
    await tester.pumpAndSettle();

    expect(find.text('Preset settings'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(4));

    await tester.enterText(find.byType(TextField).at(1), 'Mining Kit');
    await tester.tap(find.widgetWithText(GameButton, 'Save'));
    await tester.pumpAndSettle();

    expect(controller.save.equipmentPresets[1].name, 'Mining Kit');
  });

  testWidgets('saves a chosen skill icon onto a preset', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpPanel(tester, InventoryView(controller: controller));
    await tester.tap(find.text('Equipment'));
    await tester.pump();

    await tester.tap(find.byTooltip('Preset settings'));
    await tester.pumpAndSettle();

    final mining = find.byTooltip('Mining');
    await tester.ensureVisible(mining.first);
    await tester.tap(mining.first);
    await tester.pump();
    await tester.tap(find.widgetWithText(GameButton, 'Save'));
    await tester.pumpAndSettle();

    expect(controller.save.equipmentPresets[0].icon.kind, 'skill');
    expect(controller.save.equipmentPresets[0].icon.skillId, 'SKL-0002');
  });
}
