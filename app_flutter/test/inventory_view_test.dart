import 'package:flutter/gestures.dart';
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

  test('paper doll art is 10 percent smaller than the well', () {
    expect(paperDollArtSize(54), 43.2);
    expect(paperDollArtSize(20), 18.0);
  });

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

  testWidgets('right-click opens the same item detail as long-press', (tester) async {
    final seed = unequippedCharacter().copyWith(
      inventory: [const InventoryStack(itemId: 'ITEM-0002', quantity: 5)],
    );
    final controller = buildController(database, seed: seed);
    addTearDown(controller.dispose);

    await pumpPanel(tester, InventoryView(controller: controller));
    await tester.tap(find.byTooltip('Clay'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.text('×5'), findsOne);
    expect(find.textContaining('value each'), findsOne);
  });

  testWidgets('Inventory title and Close sit off the tan panel', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpPanel(tester, InventoryView(controller: controller, onClose: () {}));

    expect(find.text('Inventory'), findsOne);
    expect(find.widgetWithText(GameButton, 'Close'), findsOne);
    expect(
      find.descendant(of: find.byType(GamePanel), matching: find.text('Inventory')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(GamePanel),
        matching: find.widgetWithText(GameButton, 'Close'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: find.byType(GamePanel), matching: find.text('Sell items')),
      findsOne,
    );
  });

  testWidgets('the combined sheet shows the paper doll and the bag together', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpPanel(tester, InventoryView(controller: controller, showHeader: false));

    expect(find.text('Sell items'), findsOne);
    expect(find.textContaining('slots'), findsOne);
    expect(find.widgetWithText(GameButton, 'Attributes'), findsOne);
    expect(find.text('Damage'), findsNothing);
    expect(find.text('Helmet'), findsNothing);
    expect(find.text('Weapon or Tool'), findsNothing);
    expect(find.byKey(const Key('equipment-slot-SLOT-0003')), findsOne);
    expect(find.byTooltip('Helmet'), findsOne);
    final emptyWell = tester.widget<PixelInkPlate>(
      find.descendant(
        of: find.byKey(const Key('equipment-slot-SLOT-0003')),
        matching: find.byType(PixelInkPlate),
      ),
    );
    expect(emptyWell.fillColor, UiChrome.wood.slot);
    expect(emptyWell.material, PixelPlateMaterial.grain);
  });

  testWidgets('item total, sell, and sort sit above the bag, not the doll', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpPanel(tester, InventoryView(controller: controller));

    final helmet = tester.getRect(find.byKey(const Key('equipment-slot-SLOT-0003')));
    final sell = tester.getRect(find.text('Sell items'));
    final slots = tester.getRect(find.textContaining('slots'));
    final sort = tester.getRect(find.byTooltip('Sort'));
    final bag = tester.getRect(find.byKey(const Key('inventory-bag')));
    expect(sell.top, greaterThan(helmet.bottom));
    expect(slots.top, greaterThan(helmet.bottom));
    expect(sort.top, greaterThan(helmet.bottom));
    expect(bag.top, greaterThan(sell.bottom));
    expect(bag.top, greaterThan(slots.bottom));
    expect(bag.top, greaterThan(sort.bottom));
  });

  testWidgets('Attributes opens an overlay with damage, health, and DR', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpPanel(tester, InventoryView(controller: controller));
    expect(find.text('Damage'), findsNothing);
    expect(find.text('Health'), findsNothing);
    expect(find.text('DR'), findsNothing);
    expect(find.text('Show bonuses'), findsNothing);

    await tester.tap(find.widgetWithText(GameButton, 'Attributes'));
    await tester.pumpAndSettle();

    final popup = find.byKey(const Key('game-popup'));
    expect(popup, findsOne);
    expect(find.descendant(of: popup, matching: find.text('Attributes')), findsOne);
    expect(find.descendant(of: popup, matching: find.text('Damage')), findsOne);
    expect(find.descendant(of: popup, matching: find.text('Health')), findsOne);
    expect(find.descendant(of: popup, matching: find.text('DR')), findsOne);
    expect(find.text('Show bonuses'), findsOne);
    expect(find.text('Show sources'), findsOne);
    expect(find.text('Attack style'), findsNothing);
    expect(find.text('Offensive'), findsNothing);
    expect(find.textContaining('Eat at'), findsNothing);
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

  testWidgets('Stance opens its own menu and updates the selected style', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpPanel(tester, InventoryView(controller: controller));
    expect(controller.save.attackStyle, 'offensive');

    await tester.tap(find.byKey(const Key('inventory-stance')));
    await tester.pumpAndSettle();

    final popup = find.byKey(const Key('game-popup'));
    expect(find.descendant(of: popup, matching: find.text('Stance')), findsOne);
    expect(find.textContaining('+1% damage'), findsOne);
    expect(
      tester.widget<GameButton>(find.widgetWithText(GameButton, 'Offensive')).selected,
      isTrue,
    );

    await tester.tap(find.widgetWithText(GameButton, 'Balanced'));
    await tester.pump();
    expect(controller.save.attackStyle, 'balanced');
    expect(find.textContaining('No stance bonus'), findsOne);
    expect(tester.widget<GameButton>(find.widgetWithText(GameButton, 'Balanced')).selected, isTrue);

    await tester.tap(find.widgetWithText(GameButton, 'Defensive'));
    await tester.pump();
    expect(controller.save.attackStyle, 'defensive');
    expect(find.textContaining('+1 DR'), findsOne);
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

    expect(find.textContaining('High Elf'), findsNothing);
    await tester.tap(find.widgetWithText(GameButton, 'Attributes'));
    await tester.pumpAndSettle();
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

    expect(find.textContaining('action time'), findsNothing);
    await tester.tap(find.widgetWithText(GameButton, 'Attributes'));
    await tester.pumpAndSettle();
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
    expect(find.byKey(const Key('inventory-eat')), findsOne);
    expect(
      find.descendant(of: find.byTooltip('Wild berries').first, matching: find.text('Eat')),
      findsNothing,
    );

    await tester.longPress(find.byTooltip('Wild berries').first);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byKey(const Key('game-popup')), matching: find.text('Eat')),
      findsOne,
    );
  });

  testWidgets('applying a preset wears it; bag equips still change current gear only', (
    tester,
  ) async {
    var save = unequippedCharacter();
    save = addItemToInventory(save, 'ITEM-0111', 1);
    save = addItemToInventory(save, 'ITEM-0110', 1);
    final equipped = equipItemFromInventory(database.launch, save, 'ITEM-0111');
    expect(equipped.ok, isTrue);
    save = saveActiveEquipmentPreset(equipped.save!);

    final controller = buildController(database, seed: save);
    addTearDown(controller.dispose);

    await pumpPanel(tester, InventoryView(controller: controller));

    expect(find.text('Current'), findsNothing);
    expect(find.text('Apply'), findsNothing);
    expect(find.text('Edit'), findsNothing);

    Future<void> tapBagHatchet() async {
      final hatchet = find.descendant(
        of: find.byKey(const Key('inventory-bag')),
        matching: find.byTooltip('Copper Hatchet'),
      );
      await tester.ensureVisible(hatchet);
      await tester.tap(hatchet);
      await tester.pump();
    }

    await tapBagHatchet();

    expect(controller.save.equipment.slots['SLOT-0001']?.itemId, 'ITEM-0110');
    expect(controller.save.equipmentPresets[0].slots['SLOT-0001']?.itemId, 'ITEM-0111');

    await tester.tap(find.byKey(const Key('preset-chip-0')));
    await tester.pumpAndSettle();
    expect(find.text('Apply'), findsNothing);
    expect(controller.save.activeEquipmentPresetIndex, 0);
    expect(controller.save.equipment.slots['SLOT-0001']?.itemId, 'ITEM-0111');
    expect(controller.save.equipmentPresets[0].slots['SLOT-0001']?.itemId, 'ITEM-0111');
    Material chipMaterial(Key key) {
      return tester.widget<Material>(
        find.descendant(of: find.byKey(key), matching: find.byType(Material)),
      );
    }

    PixelSteppedBorder chipBorder(Key key) {
      return chipMaterial(key).shape! as PixelSteppedBorder;
    }

    expect(chipBorder(const Key('preset-chip-0')).side.width, 3);
    expect(chipBorder(const Key('preset-chip-0')).side.color, Palette.gold);

    final wornAgain = equipItemFromInventory(database.launch, controller.save, 'ITEM-0110');
    expect(wornAgain.ok, isTrue);
    controller.commitLoadout(wornAgain.save!);

    expect(controller.save.equipmentPresets[0].slots['SLOT-0001']?.itemId, 'ITEM-0111');
    expect(controller.save.equipment.slots['SLOT-0001']?.itemId, 'ITEM-0110');
  });

  testWidgets('Save stamps currently worn gear onto the active preset', (tester) async {
    var save = unequippedCharacter();
    save = addItemToInventory(save, 'ITEM-0111', 1);
    save = addItemToInventory(save, 'ITEM-0110', 1);
    final equipped = equipItemFromInventory(database.launch, save, 'ITEM-0111');
    expect(equipped.ok, isTrue);
    save = saveActiveEquipmentPreset(equipped.save!);

    final controller = buildController(database, seed: save);
    addTearDown(controller.dispose);

    await pumpPanel(tester, InventoryView(controller: controller));
    expect(controller.save.equipmentPresets[0].slots['SLOT-0001']?.itemId, 'ITEM-0111');

    await tester.tap(find.byTooltip('Copper Hatchet').first);
    await tester.pump();
    expect(controller.save.equipment.slots['SLOT-0001']?.itemId, 'ITEM-0110');
    expect(controller.save.equipmentPresets[0].slots['SLOT-0001']?.itemId, 'ITEM-0111');

    expect(
      tester
          .widget<InkWell>(
            find.descendant(
              of: find.byKey(const Key('save-preset')),
              matching: find.byType(InkWell),
            ),
          )
          .onTap,
      isNotNull,
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(controller.save.equipment.slots['SLOT-0001']?.itemId, 'ITEM-0110');
    expect(controller.save.equipmentPresets[0].slots['SLOT-0001']?.itemId, 'ITEM-0110');
  });

  testWidgets('opens preset settings for all four presets from equipment bar', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpPanel(tester, InventoryView(controller: controller));

    await tester.tap(find.byTooltip('Preset settings'));
    await tester.pumpAndSettle();

    expect(find.text('Preset settings'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(4));

    await tester.enterText(find.byType(TextField).at(1), 'Mining Kit');
    await tester.tap(find.widgetWithText(GameButton, 'Save'));
    await tester.pumpAndSettle();

    expect(controller.save.equipmentPresets[1].name, 'Mining Kit');
  });

  testWidgets('preset settings Save keeps name and icon on a phone sheet', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpPanel(tester, InventoryView(controller: controller), size: const Size(390, 844));

    await tester.tap(find.byTooltip('Preset settings'));
    await tester.pumpAndSettle();

    expect(tester.getRect(find.widgetWithText(GameButton, 'Save')).bottom, lessThan(844));

    await tester.enterText(find.byType(TextField).first, 'Farm Kit');
    final mining = find.byTooltip('Mining');
    await tester.ensureVisible(mining.first);
    await tester.tap(mining.first);
    await tester.pump();

    await tester.ensureVisible(find.widgetWithText(GameButton, 'Save'));
    await tester.tap(find.widgetWithText(GameButton, 'Save'));
    await tester.pumpAndSettle();

    expect(controller.save.equipmentPresets[0].name, 'Farm Kit');
    expect(controller.save.equipmentPresets[0].icon.kind, 'skill');
    expect(controller.save.equipmentPresets[0].icon.skillId, 'SKL-0002');
  });

  testWidgets('saves a chosen skill icon onto a preset', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpPanel(tester, InventoryView(controller: controller));

    await tester.tap(find.byTooltip('Preset settings'));
    await tester.pumpAndSettle();

    final mining = find.byTooltip('Mining');
    await tester.ensureVisible(mining.first);
    await tester.tap(mining.first);
    await tester.pump();

    expect(controller.save.equipmentPresets[0].icon.kind, isNot('skill'));

    await tester.ensureVisible(find.byTooltip('Coin').first);
    await tester.tap(find.byTooltip('Coin').first);
    await tester.pump();
    expect(controller.save.equipmentPresets[0].icon.kind, isNot('coin'));

    await tester.ensureVisible(mining.at(1));
    await tester.tap(mining.at(1));
    await tester.pump();
    expect(controller.save.equipmentPresets[0].icon.kind, isNot('skill'));
    expect(controller.save.equipmentPresets[1].icon.skillId, isNot('SKL-0002'));

    await tester.tap(find.widgetWithText(GameButton, 'Save'));
    await tester.pumpAndSettle();
    expect(controller.save.equipmentPresets[0].icon.kind, 'coin');
    expect(controller.save.equipmentPresets[1].icon.kind, 'skill');
    expect(controller.save.equipmentPresets[1].icon.skillId, 'SKL-0002');
  });

  testWidgets('Cancel on the preset editor drops name and icon edits', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    final beforeName = controller.save.equipmentPresets[0].name;
    final beforeIcon = controller.save.equipmentPresets[0].icon;

    await pumpPanel(tester, InventoryView(controller: controller));

    await tester.tap(find.byTooltip('Preset settings'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Farm Kit');
    final mining = find.byTooltip('Mining');
    await tester.ensureVisible(mining.first);
    await tester.tap(mining.first);
    await tester.pump();
    expect(controller.save.equipmentPresets[0].name, beforeName);

    await tester.tap(find.widgetWithText(GameButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(controller.save.equipmentPresets[0].name, beforeName);
    expect(controller.save.equipmentPresets[0].icon.kind, beforeIcon.kind);
    expect(controller.save.equipmentPresets[0].icon.skillId, beforeIcon.skillId);
  });

  testWidgets('presets sit left of the doll; Attributes and Eat sit right', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpPanel(tester, InventoryView(controller: controller));

    expect(find.byKey(const Key('current-loadout')), findsNothing);
    expect(find.byKey(const Key('preset-chip-0')), findsOne);
    expect(find.byKey(const Key('save-preset')), findsOne);
    expect(find.byKey(const Key('preset-settings')), findsOne);
    expect(find.byKey(const Key('inventory-attributes')), findsOne);
    expect(find.byKey(const Key('inventory-stance')), findsOne);
    expect(find.byKey(const Key('inventory-eat')), findsOne);
    expect(find.textContaining('Eat at'), findsNothing);

    final helmet = tester.getRect(find.byKey(const Key('equipment-slot-SLOT-0003')));
    final preset = tester.getRect(find.byKey(const Key('preset-chip-0')));
    final saveChip = tester.getRect(find.byKey(const Key('save-preset')));
    final settings = tester.getRect(find.byKey(const Key('preset-settings')));
    final attributes = tester.getRect(find.byKey(const Key('inventory-attributes')));
    final stance = tester.getRect(find.byKey(const Key('inventory-stance')));
    final eat = tester.getRect(find.byKey(const Key('inventory-eat')));
    expect(preset.right, lessThan(helmet.left));
    expect(saveChip.right, lessThan(helmet.left));
    expect(settings.right, lessThan(helmet.left));
    expect(saveChip.top, greaterThan(preset.bottom - 1));
    expect(settings.top, greaterThan(saveChip.bottom - 1));
    expect(attributes.left, greaterThan(helmet.right));
    expect(stance.left, greaterThan(helmet.right));
    expect(eat.left, greaterThan(helmet.right));
    expect(stance.top, greaterThan(attributes.bottom - 1));
    expect(eat.top, greaterThan(stance.bottom - 1));
    expect(
      tester
          .getSize(
            find.descendant(
              of: find.byKey(const Key('preset-chip-0')),
              matching: find.byType(InkWell),
            ),
          )
          .height,
      32,
    );
  });

  testWidgets('the Eat button opens the threshold picker and Auto-eat', (tester) async {
    var save = startedCharacter(database);
    save = addItemToInventory(save, 'ITEM-0028', 2);
    final equipped = equipItemFromInventory(database.launch, save, 'ITEM-0028');
    expect(equipped.ok, isTrue);
    final controller = buildController(
      database,
      seed: equipped.save!.copyWith(
        settings: equipped.save!.settings.copyWith(showEatButton: false),
      ),
    );
    addTearDown(controller.dispose);

    await pumpPanel(tester, InventoryView(controller: controller));
    expect(find.byKey(const Key('inventory-eat')), findsOne);
    expect(find.byKey(const Key('inventory-eat-now')), findsOne);
    expect(find.textContaining('Eat at'), findsNothing);

    await tester.tap(find.byKey(const Key('inventory-eat')));
    await tester.pumpAndSettle();

    final popup = find.byKey(const Key('game-popup'));
    expect(popup, findsOne);
    expect(find.textContaining('Eat at'), findsOne);
    expect(find.byKey(const Key('auto-eat')), findsOne);
    expect(find.text('Auto-eat on'), findsOne);
    expect(find.byKey(const Key('eat-now')), findsNothing);

    await tester.tap(find.byKey(const Key('auto-eat')));
    await tester.pump();
    expect(controller.autoEat, isFalse);
    expect(find.text('Auto-eat off'), findsOne);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    final before = controller.save.equipment.slots[foodSlotId]?.quantity ?? 0;
    expect(before, greaterThan(0));
    await tester.tap(find.byKey(const Key('inventory-eat-now')));
    await tester.pumpAndSettle();
    expect(controller.save.equipment.slots[foodSlotId]?.quantity ?? 0, before - 1);
  });

  testWidgets('Eat now with an empty food slot says so', (tester) async {
    final controller = buildController(database, seed: unequippedCharacter());
    addTearDown(controller.dispose);

    await pumpPanel(tester, InventoryView(controller: controller));
    await tester.tap(find.byKey(const Key('inventory-eat-now')));
    await tester.pump();
    expect(find.text('Nothing to eat.'), findsOne);
  });

  testWidgets('the doll row stays usable on a phone-wide sheet', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpPanel(tester, InventoryView(controller: controller), size: const Size(390, 844));

    final helmet = tester.getRect(find.byKey(const Key('equipment-slot-SLOT-0003')));
    expect(helmet.width, greaterThan(36));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('preset-chip-0')), findsOne);
    expect(find.byKey(const Key('inventory-eat')), findsOne);
  });

  testWidgets('the bag fits six to eight items on a row', (tester) async {
    final seed = unequippedCharacter().copyWith(
      inventory: [for (var i = 0; i < 16; i += 1) InventoryStack(itemId: 'ITEM-0002', quantity: 1)],
    );
    final controller = buildController(database, seed: seed);
    addTearDown(controller.dispose);

    await pumpPanel(tester, InventoryView(controller: controller), size: const Size(420, 2400));

    final clay = find.byTooltip('Clay');
    expect(clay, findsWidgets);
    final firstRowTop = tester.getRect(clay.at(0)).center.dy;
    var columns = 0;
    for (var i = 0; i < clay.evaluate().length; i += 1) {
      if ((tester.getRect(clay.at(i)).center.dy - firstRowTop).abs() < 8) {
        columns += 1;
      }
    }
    expect(columns, inInclusiveRange(6, 8));
  });
}
