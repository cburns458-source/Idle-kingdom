import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/bag_overflow_pref.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/bank_panel.dart';
import 'package:idle_kingdoms/src/ui/dialogue_text.dart';
import 'package:idle_kingdoms/src/ui/dialogue_window.dart';
import 'package:idle_kingdoms/src/ui/inventory_view.dart';
import 'package:idle_kingdoms/src/ui/left_behind_popup.dart';
import 'package:idle_kingdoms/src/ui/npc_panel.dart';
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
    expect(storage.getItem(pref.storageKey), '1');
    expect(BagOverflowPref.load(storage).hasBadge, isTrue);

    pref.setHasBadge(false);
    expect(pref.hasBadge, isFalse);
    expect(storage.getItem(pref.storageKey), '0');
  });

  test('a new account does not inherit another save\'s bag-overflow badge', () {
    final storage = MemorySaveStorage();
    final testerSave = startedCharacter(database);
    final testerPref = BagOverflowPref.load(storage, identity: testerSave.createdAt);
    testerPref.setHasBadge(true);
    expect(storage.getItem(BagOverflowPref.storageKeyFor(testerSave.createdAt)), '1');

    final otherSave = testerSave.copyWith(
      characterName: 'Other',
      createdAt: '2026-02-01T00:00:00.000Z',
    );
    final other = buildController(
      database,
      seed: otherSave,
      bagOverflow: BagOverflowPref.load(storage),
    );
    addTearDown(other.dispose);
    expect(other.hasBagOverflowBadge, isFalse);
    expect(other.bagOverflow.identity, otherSave.createdAt);
    expect(storage.getItem(BagOverflowPref.storageKeyFor(testerSave.createdAt)), '1');
    expect(storage.getItem(other.bagOverflow.storageKey), isNot('1'));

    final stillTester = buildController(
      database,
      seed: testerSave,
      bagOverflow: BagOverflowPref.load(storage),
    );
    addTearDown(stillTester.dispose);
    expect(stillTester.hasBagOverflowBadge, isTrue);
    expect(stillTester.bagOverflow.identity, testerSave.createdAt);
  });

  test('the bag-overflow badge migrates from a name-keyed pref', () {
    final storage = MemorySaveStorage();
    final save = startedCharacter(database);
    storage.setItem(BagOverflowPref.storageKeyFor(save.characterName), '1');

    final controller = buildController(
      database,
      seed: save,
      bagOverflow: BagOverflowPref.load(storage),
    );
    addTearDown(controller.dispose);

    expect(controller.hasBagOverflowBadge, isTrue);
    expect(controller.bagOverflow.identity, save.createdAt);
    expect(storage.getItem(BagOverflowPref.storageKeyFor(save.createdAt)), '1');
    expect(storage.getItem(BagOverflowPref.storageKeyFor(save.characterName)), isNull);
  });

  test('migrating the bag-overflow badge deletes the leftover name-keyed value', () {
    final storage = MemorySaveStorage();
    const createdAt = '2026-01-01T00:00:00.000Z';
    const name = 'Tester';
    storage.setItem(BagOverflowPref.storageKeyFor(name), '1');

    final pref = BagOverflowPref.load(storage, identity: createdAt, legacyName: name);
    expect(pref.hasBadge, isTrue);
    expect(storage.getItem(BagOverflowPref.storageKeyFor(createdAt)), '1');
    expect(storage.getItem(BagOverflowPref.storageKeyFor(name)), isNull);

    storage.setItem(BagOverflowPref.storageKeyFor(name), '0');
    final off = BagOverflowPref.load(storage, identity: 'other-save', legacyName: name);
    expect(off.hasBadge, isFalse);
    expect(storage.getItem(BagOverflowPref.storageKeyFor('other-save')), '0');
    expect(storage.getItem(BagOverflowPref.storageKeyFor(name)), isNull);
  });

  test('the bag-overflow badge survives a rename', () {
    final storage = MemorySaveStorage();
    final save = startedCharacter(database);
    final controller = buildController(
      database,
      seed: save,
      bagOverflow: BagOverflowPref.load(storage),
    );
    addTearDown(controller.dispose);
    controller.noteLeftBehind(const [LootGrant(itemId: clayId, quantity: 1, displayName: 'Clay')]);
    expect(controller.hasBagOverflowBadge, isTrue);

    controller.commit(controller.save.copyWith(characterName: 'Renamed'));
    expect(controller.save.characterName, 'Renamed');
    expect(controller.hasBagOverflowBadge, isTrue);
    expect(controller.bagOverflow.identity, save.createdAt);

    final restored = buildController(
      database,
      seed: controller.save,
      bagOverflow: BagOverflowPref.load(storage, identity: controller.save.createdAt),
    );
    addTearDown(restored.dispose);
    expect(restored.hasBagOverflowBadge, isTrue);
    expect(restored.bagOverflow.identity, save.createdAt);
  });

  test('the bag-overflow badge survives sign-out', () {
    final storage = MemorySaveStorage();
    final clock = TestClock();
    final save = startedCharacter(database);
    final controller = buildController(
      database,
      seed: save,
      clock: clock,
      bagOverflow: BagOverflowPref.load(storage),
    );
    addTearDown(controller.dispose);
    controller.noteLeftBehind(const [LootGrant(itemId: clayId, quantity: 1, displayName: 'Clay')]);
    final saveKey = controller.bagOverflow.storageKey;
    expect(storage.getItem(saveKey), '1');

    clock.advance(60 * 1000);
    controller.resetUnsigned();
    expect(storage.getItem(saveKey), '1');
    expect(controller.hasBagOverflowBadge, isFalse);
    expect(controller.bagOverflow.identity, isNot(save.createdAt));

    controller.adoptAccountSave(save);
    expect(controller.hasBagOverflowBadge, isTrue);
    expect(controller.bagOverflow.identity, save.createdAt);
  });

  test('no_room copy covers stack_full, bank-full, and bag-full', () {
    expect(DialogueText.noRoomPopup(const NoRoom(reason: 'stack_full')), DialogueText.stackFull);
    expect(DialogueText.stackFull, 'That stack is full.');
    expect(DialogueText.stackFull, isNot(contains('cannot hold')));
    expect(DialogueText.stackFull.contains(RegExp(r'\d')), isFalse);
    expect(
      bankNoRoomMessage(const NoRoom(target: 'bank', slotsNeeded: 1, slotsFree: 0)),
      'Your bank is full. Make room for 1 more item and try again.',
    );
    expect(
      bankNoRoomMessage(const NoRoom(target: 'bank', slotsNeeded: 3, slotsFree: 0)),
      'Your bank is full. Make room for 3 more items and try again.',
    );
    expect(DialogueText.bagFull(1), 'Your bag is full. Make room for 1 more item and try again.');
    expect(
      DialogueText.noRoomPopup(const NoRoom(slotsNeeded: 2, slotsFree: 0)),
      'Your bag is full. Make room for 2 more items and try again.',
    );
    expect(DialogueText.moreItems(1), '1 more item');
    expect(DialogueText.moreItems(3), '3 more items');
    expect(DialogueText.moreItems(0), '1 more item');
    expect(DialogueText.moreItems(-4), '1 more item');
    expect(
      DialogueText.noRoomPopup(const NoRoom(slotsNeeded: 0, slotsFree: 0)),
      DialogueText.bagFull(1),
    );
    expect(
      DialogueText.noRoomPopup(const NoRoom(slotsNeeded: -2, slotsFree: 0)),
      DialogueText.bagFull(1),
    );
    expect(
      bankNoRoomMessage(const NoRoom(target: 'bank', slotsNeeded: 0, slotsFree: 0)),
      'Your bank is full. Make room for 1 more item and try again.',
    );
    expect(
      DialogueText.noRoomPopup(
        const NoRoom(slotsNeeded: 1, slotsFree: 0, npcLine: 'Clear some space.'),
      ),
      DialogueText.bagFull(1),
    );
    expect(
      bankNoRoomMessage(
        const NoRoom(target: 'bank', slotsNeeded: 1, slotsFree: 0, npcLine: 'Clear some space.'),
      ),
      'Your bank is full. Make room for 1 more item and try again.',
    );
    expect(DialogueText.spokenNpcLine(null), isNull);
    expect(DialogueText.spokenNpcLine(const NoRoom(slotsNeeded: 1)), isNull);
    expect(DialogueText.spokenNpcLine(const NoRoom(npcLine: '')), isNull);
    expect(DialogueText.spokenNpcLine(const NoRoom(npcLine: '   ')), isNull);
    expect(
      DialogueText.spokenNpcLine(const NoRoom(npcLine: '  Clear some space.  ')),
      'Clear some space.',
    );
    expect(
      DialogueText(database.launch).failure(
        DialogueResult(
          ok: false,
          reason: 'That stack cannot hold more of this item.',
          code: 'no_room',
          save: startedCharacter(database),
          view: null,
          completed: false,
          message: null,
          noRoom: const NoRoom(reason: 'stack_full'),
        ),
      ),
      DialogueText.stackFull,
    );
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
    expect(storage.getItem(controller.bagOverflow.storageKey), '1');

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
    expect(storage.getItem(controller.bagOverflow.storageKey), '0');
    expect(controller.hasBagOverflowBadge, isFalse);
  });

  testWidgets('the bag badge stays after a rename', (tester) async {
    final storage = MemorySaveStorage();
    final controller = buildController(
      database,
      seed: startedCharacter(database),
      bagOverflow: BagOverflowPref.load(storage),
    );
    addTearDown(controller.dispose);

    await pumpShell(tester, controller, size: const Size(390, 844));
    controller.noteLeftBehind(const [LootGrant(itemId: clayId, quantity: 1, displayName: 'Clay')]);
    await pumpPopup(tester);
    expect(bagBadgeBubble(), findsOne);

    await tester.tap(find.text('OK'));
    await pumpPopup(tester);
    controller.commit(controller.save.copyWith(characterName: 'Renamed'));
    await tester.pump();

    expect(controller.save.characterName, 'Renamed');
    expect(bagBadgeBubble(), findsOne);
    expect(storage.getItem(BagOverflowPref.storageKeyFor(controller.save.createdAt)), '1');
  });

  testWidgets('the bag badge stays after sign-out and sign-in', (tester) async {
    final storage = MemorySaveStorage();
    final clock = TestClock();
    final save = startedCharacter(database);
    final controller = buildController(
      database,
      seed: save,
      clock: clock,
      bagOverflow: BagOverflowPref.load(storage),
    );
    addTearDown(controller.dispose);

    await pumpShell(tester, controller, size: const Size(390, 844));
    controller.noteLeftBehind(const [LootGrant(itemId: clayId, quantity: 1, displayName: 'Clay')]);
    await pumpPopup(tester);
    await tester.tap(find.text('OK'));
    await pumpPopup(tester);
    expect(bagBadgeBubble(), findsOne);

    clock.advance(60 * 1000);
    controller.resetUnsigned();
    await tester.pump();
    expect(bagBadgeBubble(), findsNothing);
    expect(storage.getItem(BagOverflowPref.storageKeyFor(save.createdAt)), '1');

    controller.adoptAccountSave(save);
    await tester.pump();
    expect(bagBadgeBubble(), findsOne);
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

  test('offline catch-up does not count left-behind twice through noteReward', () {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    const grants = [
      LootGrant(itemId: clayId, quantity: 4, displayName: 'Clay'),
      LootGrant(itemId: oreId, quantity: 2, displayName: 'Copper Ore'),
    ];
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
          leftBehind: grants,
        ),
      ),
    );

    expect(controller.recentRewards, isEmpty);
    expect(
      [for (final grant in controller.pendingLeftBehind) (grant.itemId, grant.quantity)],
      [(clayId, 4), (oreId, 2)],
    );
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
    expect(find.textContaining('Clear some space'), findsNothing);
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
    expect(find.textContaining('Clear some space'), findsNothing);
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
    expect(find.textContaining('Clear some space'), findsNothing);
    expect(controller.mailboxClaimCalls, 1);
    expect(
      controller.save.mailbox.where((message) => message.id == 'mail-full').single.claimedAt,
      isNull,
    );
    expect(controller.save.inventory, hasLength(inventorySlotLimit));
  });

  testWidgets('pumping InventoryView does not notify during build or clear the badge', (
    tester,
  ) async {
    final storage = MemorySaveStorage();
    final controller = buildController(
      database,
      seed: startedCharacter(database),
      bagOverflow: BagOverflowPref.load(storage),
    );
    addTearDown(controller.dispose);
    controller.noteLeftBehind(const [LootGrant(itemId: clayId, quantity: 1, displayName: 'Clay')]);
    expect(controller.hasBagOverflowBadge, isTrue);

    final duringBuild = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('during build')) {
        duringBuild.add(details.toString());
      }
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);

    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => InventoryView(controller: controller),
          ),
        ),
      ),
    );

    expect(duringBuild, isEmpty);
    expect(controller.hasBagOverflowBadge, isTrue);
    expect(storage.getItem(controller.bagOverflow.storageKey), '1');
  });

  testWidgets('quest reward no_room names the slots and commits nothing', (tester) async {
    // Qty 6 leaves each delivery pile in place, so turning in frees no slot.
    // Chef's Hat then needs one new slot against a full bag.
    const roseId = 'NPC-0005';
    const roseQuest = 'QST-0002';
    const rabbitsFoot = 'ITEM-0038';
    const fernleaf = 'ITEM-0031';
    const wildBerries = 'ITEM-0028';
    const weaselTail = 'ITEM-0042';
    const chefHat = 'ITEM-0165';
    InventoryStack stack(String itemId) => InventoryStack(itemId: itemId, quantity: 6);
    var seed = startedCharacter(database).copyWith(
      currentLocationId: 'LOC-0023',
      gold: 1500,
      inventory: [stack(rabbitsFoot), stack(fernleaf), stack(wildBerries), stack(weaselTail)],
      quests: const [QuestProgress(questId: roseQuest, status: 'active', progress: 0)],
    );
    final inventory = [...seed.inventory];
    for (var index = 0; inventory.length < inventorySlotLimit; index++) {
      inventory.add(InventoryStack(itemId: 'ITEM-FILL-$index', quantity: 1));
    }
    seed = seed.copyWith(inventory: inventory);

    final controller = buildController(database, seed: seed);
    addTearDown(controller.dispose);
    final rose = database.launch.npcs.firstWhere((row) => row.raw['NPC ID'] == roseId);
    await pumpPanel(tester, NpcPanel(controller: controller, npc: rose, onClose: () {}));
    await tester.tap(find.text('Continue'));
    await tester.pump();
    final before = jsonEncode(controller.save.toJson());

    await tester.tap(find.text('Turn in'));
    await tester.pumpAndSettle();

    expect(find.text(DialogueText.bagFull(1)), findsOne);
    expect(jsonEncode(controller.save.toJson()), before);
    expect(getQuestProgress(controller.save, roseQuest).status, 'active');
    expect(controller.save.gold, 1500);
    expect(controller.save.inventory.any((stack) => stack.itemId == chefHat), isFalse);
    expect(controller.recentRewards, isEmpty);
  });

  testWidgets('Green Thumb gift no_room leaves the seed and gift flag unset', (tester) async {
    // Dialogue grant_item + gift:QST-0011:seed. The existing DCH-9025 case in
    // dialogue_window_test already covers a full-bag grant_item popup.
    var save = startedCharacter(database).copyWith(
      currentLocationId: 'LOC-0001',
      quests: [
        for (final quest in startedCharacter(database).quests)
          if (quest.questId != 'QST-0006' && quest.questId != 'QST-0011') quest,
        const QuestProgress(questId: 'QST-0006', status: 'completed', progress: 1),
      ],
    );
    save = addItemToInventory(save, 'ITEM-0339', 1);
    save = applyQuestAutoStartOnSeed(database.launch, save);
    expect(getQuestProgress(save, 'QST-0011').status, 'active');
    final inventory = [...save.inventory];
    for (var index = 0; inventory.length < inventorySlotLimit; index++) {
      inventory.add(InventoryStack(itemId: 'ITEM-FILL-$index', quantity: 1));
    }
    save = save.copyWith(inventory: inventory);

    final controller = buildController(database, seed: save);
    addTearDown(controller.dispose);
    final before = jsonEncode(controller.save.toJson());
    await pumpPanel(
      tester,
      StandaloneDialogueHost(controller: controller, dialogueId: 'DLG-0007', onClose: () {}),
    );

    expect(
      find.text(
        "Oh, you've found a seed! Let me take a look... That will grow into a mighty plant one day. Practise on one of mine first.",
      ),
      findsOne,
    );
    await tester.tap(find.text("I'd like that."));
    await tester.pumpAndSettle();

    expect(
      find.text(
        "You're carrying too much for a harvest gift. Clear some space and come back to me.",
      ),
      findsOne,
    );
    expect(find.text(DialogueText.bagFull(1)), findsOne);
    expect(jsonEncode(controller.save.toJson()), before);
    expect(controller.save.dialogueFlags, isNot(contains('gift:QST-0011:seed')));
    expect(controller.save.inventory.any((stack) => stack.itemId == 'ITEM-0324'), isFalse);
  });

  testWidgets('Guide potato no_room shows the make-room line under the count popup', (
    tester,
  ) async {
    var save = startedCharacter(database).copyWith(currentLocationId: 'LOC-0028');
    final inventory = [...save.inventory];
    for (var index = 0; inventory.length < inventorySlotLimit; index++) {
      inventory.add(InventoryStack(itemId: 'ITEM-FILL-$index', quantity: 1));
    }
    save = save.copyWith(inventory: inventory);

    final controller = buildController(database, seed: save);
    addTearDown(controller.dispose);
    final before = jsonEncode(controller.save.toJson());
    await pumpPanel(
      tester,
      StandaloneDialogueHost(controller: controller, dialogueId: 'DLG-0001', onClose: () {}),
    );

    expect(find.text('Welcome to the Citadel. Need a tip for the road?'), findsOne);
    await tester.tap(find.text('Yes, please.'));
    await tester.pumpAndSettle();

    expect(
      find.text("Your pack's stuffed full, friend. Clear some space and come back to me."),
      findsOne,
    );
    expect(find.text(DialogueText.bagFull(1)), findsOne);
    expect(find.text('Welcome to the Citadel. Need a tip for the road?'), findsNothing);
    expect(jsonEncode(controller.save.toJson()), before);
    expect(controller.save.dialogueFlags, isNot(contains('gift:DLG-0001:potato')));
    expect(controller.save.inventory.any((stack) => stack.itemId == 'ITEM-0058'), isFalse);
  });

  testWidgets('shop buy stack_full says the stack is full and never names a count', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(
        currentLocationId: shopLocationId,
        gold: 1000,
        inventory: [
          const InventoryStack(itemId: 'ITEM-0100', quantity: inventoryStackMax, favorite: true),
          const InventoryStack(itemId: clayId, quantity: 1),
        ],
      ),
    );
    addTearDown(controller.dispose);

    await pumpPanel(tester, ShopPanel(controller: controller, shopId: shopId));
    await tester.tap(find.byTooltip('Wooden Axe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to offer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm trade'));
    await tester.pumpAndSettle();

    expect(find.text(DialogueText.stackFull), findsOne);
    expect(find.textContaining('Make room'), findsNothing);
    expect(find.textContaining('cannot hold'), findsNothing);
    expect(controller.save.gold, 1000);
    expect(
      controller.save.inventory.where((stack) => stack.itemId == 'ITEM-0100').single.quantity,
      inventoryStackMax,
    );
  });

  testWidgets('bank withdraw stack_full says the stack is full', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(
        inventory: const [InventoryStack(itemId: clayId, quantity: inventoryStackMax)],
        bank: const [InventoryStack(itemId: clayId, quantity: 2)],
      ),
    );
    addTearDown(controller.dispose);

    await pumpPanel(tester, BankPanel(controller: controller));
    await tester.tap(find.byKey(const ValueKey('bank-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Max'));
    await tester.pump();
    await tester.tap(find.text('Withdraw'));
    await tester.pumpAndSettle();

    expect(find.text(DialogueText.stackFull), findsOne);
    expect(find.textContaining('Make room'), findsNothing);
    expect(controller.save.bank.single.quantity, 2);
    expect(controller.save.inventory.single.quantity, inventoryStackMax);
  });

  testWidgets('bank deposit no_room with target bank shows the bank-full popup', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(
        inventory: const [InventoryStack(itemId: clayId, quantity: 1)],
        bank: [
          for (var index = 0; index < bankSlotLimit; index++)
            InventoryStack(itemId: 'BANK-$index', quantity: 1),
        ],
      ),
    );
    addTearDown(controller.dispose);

    await pumpPanel(tester, BankPanel(controller: controller));
    await tester.tap(find.byKey(const ValueKey('bag-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Max'));
    await tester.pump();
    await tester.tap(find.text('Deposit'));
    await tester.pumpAndSettle();

    expect(find.text(bankNoRoomMessage(const NoRoom(target: 'bank', slotsNeeded: 1))), findsOne);
    expect(find.textContaining('Clear some space'), findsNothing);
    expect(controller.save.inventory.single.itemId, clayId);
    expect(controller.save.bank, hasLength(bankSlotLimit));
  });

  testWidgets('enchanted withdraw into a full bag shows the make-room popup', (tester) async {
    const copperAxe = 'ITEM-0132';
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(
        inventory: [
          const InventoryStack(itemId: copperAxe, quantity: 1),
          for (var index = 0; index < inventorySlotLimit - 1; index++)
            InventoryStack(itemId: 'FILL-$index', quantity: 1),
        ],
        bank: const [InventoryStack(itemId: copperAxe, quantity: 1, enchantmentId: 'ENCH-0001')],
      ),
    );
    addTearDown(controller.dispose);

    await pumpPanel(tester, BankPanel(controller: controller));
    await tester.tap(find.byKey(const ValueKey('bank-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Max'));
    await tester.pump();
    await tester.tap(find.text('Withdraw'));
    await tester.pumpAndSettle();

    expect(find.text(DialogueText.bagFull(1)), findsOne);
    expect(find.text(DialogueText.stackFull), findsNothing);
    expect(controller.save.bank.single.enchantmentId, 'ENCH-0001');
    expect(controller.save.inventory, hasLength(inventorySlotLimit));
  });

  testWidgets('mail claim stack_full says the stack is full', (tester) async {
    final gift = MailMessage(
      id: 'mail-stack',
      catalogId: null,
      subject: 'More clay',
      body: 'Try this.',
      sentAt: isoFromMs(testStartMs),
      readAt: null,
      attachments: const [MailAttachment(itemId: clayId, quantity: 1)],
      claimedAt: null,
    );
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(
        inventory: const [InventoryStack(itemId: clayId, quantity: inventoryStackMax)],
        mailbox: [gift],
      ),
    );
    addTearDown(controller.dispose);

    await pumpShell(tester, controller, size: const Size(900, 1600));
    await tester.tap(find.byKey(const Key('mailbox-button')));
    await pumpPopup(tester);
    await tester.tap(find.byKey(const Key('mailbox-row-mail-stack')));
    await tester.pump();
    await tester.tap(find.text('Claim'));
    await pumpPopup(tester);

    expect(find.text(DialogueText.stackFull), findsOne);
    expect(controller.mailboxClaimCalls, 1);
    expect(
      controller.save.mailbox.where((message) => message.id == 'mail-stack').single.claimedAt,
      isNull,
    );
  });

  testWidgets('Beggar bribe no_room takes no gold and sets no flag', (tester) async {
    const purseId = 'ITEM-0299';
    const questId = 'QST-0003';
    var seed = startedCharacter(database).copyWith(
      currentLocationId: 'LOC-0017',
      gold: 300,
      inventory: filledBag(),
      quests: const [QuestProgress(questId: questId, status: 'active', progress: 0)],
    );
    seed = applyQuestTalkProgress(database.launch, seed, 'NPC-0011');
    final controller = buildController(database, seed: seed);
    addTearDown(controller.dispose);
    final guard = database.launch.npcs.firstWhere((row) => row.raw['NPC ID'] == 'NPC-0012');
    await pumpPanel(tester, NpcPanel(controller: controller, npc: guard, onClose: () {}));
    await tester.tap(find.text('Continue'));
    await tester.pump();
    final before = jsonEncode(controller.save.toJson());

    await tester.tap(find.text('Bribe 200 gold'));
    await tester.pumpAndSettle();

    expect(find.text(DialogueText.bagFull(1)), findsOne);
    expect(jsonEncode(controller.save.toJson()), before);
    expect(controller.save.gold, 300);
    expect(controller.save.inventory.any((stack) => stack.itemId == purseId), isFalse);
    expect(hasQuestFlag(controller.save, questId, 'choice:bribe'), isFalse);
  });
}
