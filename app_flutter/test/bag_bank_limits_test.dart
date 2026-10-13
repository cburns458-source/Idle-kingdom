import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/bag_overflow_pref.dart';
import 'package:idle_kingdoms/src/ui/bank_panel.dart';
import 'package:idle_kingdoms/src/ui/inventory_view.dart';
import 'package:idle_kingdoms/src/ui/left_behind_popup.dart';
import 'package:idle_kingdoms/src/ui/notification_bubble.dart';
import 'package:idle_kingdoms/src/ui/shop_panel.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  const shopId = 'SHP-0001';
  const shopLocationId = 'LOC-0024';
  const clayId = 'ITEM-0002';
  const oreId = 'ITEM-0003';

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  List<InventoryStack> filledBag({int free = 0}) {
    return [
      for (var index = 0; index < inventorySlotLimit - free; index++)
        InventoryStack(itemId: 'FILL-$index', quantity: 1),
    ];
  }

  Finder bagBadgeBubble() {
    return find.descendant(
      of: find.byKey(const Key('bag-overflow-badge')),
      matching: find.byType(NotificationBubble),
    );
  }

  Future<void> pumpPopup(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  ActionRewardBundle overflowBundle(String id, List<LootGrant> leftBehind) {
    return ActionRewardBundle(
      id: id,
      xpRewards: const [],
      loot: const [],
      goldGained: 0,
      leftBehind: leftBehind,
    );
  }

  test('the bag-overflow badge stays on this device', () {
    final storage = MemorySaveStorage();
    final pref = BagOverflowPref.load(storage);
    expect(pref.hasBadge, isFalse);

    pref.setHasBadge(true);
    expect(pref.hasBadge, isTrue);
    expect(storage.getItem(BagOverflowPref.storageKey), '1');
    expect(BagOverflowPref.load(storage).hasBadge, isTrue);

    pref.setHasBadge(false);
    expect(pref.hasBadge, isFalse);
    expect(storage.getItem(BagOverflowPref.storageKey), '0');
  });

  testWidgets('the bag labels used / 84 from inventorySlotLimit', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpPanel(tester, InventoryView(controller: controller));
    expect(inventorySlotLimit, 84);
    expect(
      find.text('${inventorySlotCount(controller.save)} / $inventorySlotLimit slots'),
      findsOne,
    );
  });

  testWidgets('the bank labels bag / 84 and chest / 168 from ik_rules', (tester) async {
    final seed = startedCharacter(database).copyWith(
      inventory: const [InventoryStack(itemId: clayId, quantity: 2)],
      bank: const [InventoryStack(itemId: oreId, quantity: 3)],
    );
    final controller = buildController(database, seed: seed);
    addTearDown(controller.dispose);

    await pumpPanel(tester, BankPanel(controller: controller));
    expect(inventorySlotLimit, 84);
    expect(bankSlotLimit, 168);
    expect(find.text('Bag 1/$inventorySlotLimit · Bank 1/$bankSlotLimit'), findsOne);
  });

  testWidgets('left-behind loot shows one popup listing each item', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpShell(tester, controller, size: const Size(390, 844));
    controller.noteReward(
      overflowBundle('tick-1', const [
        LootGrant(itemId: clayId, quantity: 2, displayName: 'Clay'),
        LootGrant(itemId: oreId, quantity: 1, displayName: 'Copper Ore'),
      ]),
    );
    await pumpPopup(tester);

    expect(find.text(leftBehindPopupMessage), findsOne);
    expect(find.text('Clay x2'), findsOne);
    expect(find.text('Copper Ore x1'), findsOne);
  });

  testWidgets('a second overflow batch merges into the open popup', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpShell(tester, controller, size: const Size(390, 844));
    controller.noteReward(
      overflowBundle('tick-1', const [LootGrant(itemId: clayId, quantity: 2, displayName: 'Clay')]),
    );
    await pumpPopup(tester);
    expect(find.text(leftBehindPopupMessage), findsOne);
    expect(find.text('Clay x2'), findsOne);

    controller.noteReward(
      overflowBundle('tick-2', const [
        LootGrant(itemId: clayId, quantity: 1, displayName: 'Clay'),
        LootGrant(itemId: oreId, quantity: 3, displayName: 'Copper Ore'),
      ]),
    );
    await tester.pump();

    expect(find.text(leftBehindPopupMessage), findsOne);
    expect(find.text('Clay x3'), findsOne);
    expect(find.text('Copper Ore x3'), findsOne);
  });

  testWidgets('the bag badge shows, survives rebuild, and clears when the bag opens', (
    tester,
  ) async {
    final storage = MemorySaveStorage();
    final controller = buildController(
      database,
      seed: startedCharacter(database),
      bagOverflow: BagOverflowPref.load(storage),
    );
    addTearDown(controller.dispose);

    await pumpShell(tester, controller, size: const Size(390, 844));
    expect(bagBadgeBubble(), findsNothing);

    controller.noteLeftBehind(const [LootGrant(itemId: clayId, quantity: 1, displayName: 'Clay')]);
    await pumpPopup(tester);
    expect(bagBadgeBubble(), findsOne);
    expect(storage.getItem(BagOverflowPref.storageKey), '1');

    await tester.tap(find.text('OK'));
    await pumpPopup(tester);
    expect(find.text(leftBehindPopupMessage), findsNothing);
    expect(bagBadgeBubble(), findsOne);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pumpShell(tester, controller, size: const Size(390, 844));
    expect(bagBadgeBubble(), findsOne);

    final restored = buildController(
      database,
      seed: startedCharacter(database),
      bagOverflow: BagOverflowPref.load(storage),
    );
    addTearDown(restored.dispose);
    expect(restored.hasBagOverflowBadge, isTrue);

    await openChinInventory(tester);
    await tester.pump();
    expect(bagBadgeBubble(), findsNothing);
    expect(storage.getItem(BagOverflowPref.storageKey), '0');
    expect(controller.hasBagOverflowBadge, isFalse);
  });

  testWidgets('offline catch-up shows one merged left-behind popup', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    controller.adoptBoot(
      SessionBoot(
        save: controller.save,
        created: false,
        unattended: UnattendedResult(
          save: controller.save,
          changed: true,
          messages: const [leftBehindAwayLine],
          gatheringActions: 4,
          craftsCompleted: 0,
          combatVictories: 0,
          combatDeaths: 0,
          crittersSpawned: 0,
          effectiveElapsedMs: 0,
          leftBehind: const [
            LootGrant(itemId: clayId, quantity: 4, displayName: 'Clay'),
            LootGrant(itemId: oreId, quantity: 2, displayName: 'Copper Ore'),
          ],
        ),
      ),
    );

    await pumpShell(tester, controller, size: const Size(390, 844));
    expect(find.text('While you were away'), findsOne);
    expect(find.text(leftBehindPopupMessage), findsNothing);

    await tester.tap(find.text('Continue'));
    await pumpPopup(tester);

    expect(find.text(leftBehindPopupMessage), findsOne);
    expect(find.text('Clay x4'), findsOne);
    expect(find.text('Copper Ore x2'), findsOne);
  });

  testWidgets('shop buy no_room names the slots the offer needs', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database)
          .copyWith(currentLocationId: shopLocationId, gold: 1000, inventory: filledBag()),
    );
    addTearDown(controller.dispose);

    await pumpPanel(tester, ShopPanel(controller: controller, shopId: shopId));
    await tester.tap(find.byTooltip('Wooden Axe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to offer'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Wooden Hatchet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to offer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm trade'));
    await tester.pumpAndSettle();

    expect(find.text('Your bag is full. Make room for 2 more items and try again.'), findsOne);
    expect(controller.save.gold, 1000);
    expect(controller.save.inventory, hasLength(inventorySlotLimit));
  });

  testWidgets('bank withdraw no_room names the slots the stack needs', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(
        inventory: filledBag(),
        bank: const [InventoryStack(itemId: clayId, quantity: 3)],
      ),
    );
    addTearDown(controller.dispose);

    await pumpPanel(tester, BankPanel(controller: controller));
    await tester.tap(find.byTooltip('Clay'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Max'));
    await tester.pump();
    await tester.tap(find.text('Withdraw'));
    await tester.pumpAndSettle();

    expect(find.text('Your bag is full. Make room for 1 more item and try again.'), findsOne);
    expect(controller.save.bank.single.quantity, 3);
    expect(controller.save.inventory, hasLength(inventorySlotLimit));
  });

  testWidgets('mail claim no_room names the slots the attachments need', (tester) async {
    final gift = MailMessage(
      id: 'mail-full',
      catalogId: null,
      subject: 'A parcel',
      body: 'Try this.',
      sentAt: isoFromMs(testStartMs),
      readAt: null,
      attachments: const [
        MailAttachment(itemId: clayId, quantity: 1),
        MailAttachment(itemId: oreId, quantity: 1),
        MailAttachment(itemId: 'ITEM-0025', quantity: 1),
      ],
      claimedAt: null,
    );
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(inventory: filledBag(), mailbox: [gift]),
    );
    addTearDown(controller.dispose);

    await pumpShell(tester, controller, size: const Size(900, 1600));
    await tester.tap(find.byKey(const Key('mailbox-button')));
    await pumpPopup(tester);
    await tester.tap(find.byKey(const Key('mailbox-row-mail-full')));
    await tester.pump();
    await tester.tap(find.text('Claim'));
    await pumpPopup(tester);

    expect(find.text('Your bag is full. Make room for 3 more items and try again.'), findsOne);
    expect(
      controller.save.mailbox.where((message) => message.id == 'mail-full').single.claimedAt,
      isNull,
    );
    expect(controller.save.inventory, hasLength(inventorySlotLimit));
  });
}
