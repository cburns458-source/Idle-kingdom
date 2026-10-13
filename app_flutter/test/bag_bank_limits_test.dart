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
    final testerPref = BagOverflowPref.load(storage, identity: 'Tester');
    testerPref.setHasBadge(true);
    expect(storage.getItem(BagOverflowPref.storageKeyFor('Tester')), '1');

    final other = buildController(
      database,
      seed: startedCharacter(database).copyWith(characterName: 'Other'),
      bagOverflow: BagOverflowPref.load(storage),
    );
    addTearDown(other.dispose);
    expect(other.hasBagOverflowBadge, isFalse);
    expect(other.bagOverflow.identity, 'Other');
    expect(storage.getItem(BagOverflowPref.storageKeyFor('Tester')), '1');
    expect(storage.getItem(other.bagOverflow.storageKey), isNot('1'));

    final stillTester = buildController(
      database,
      seed: startedCharacter(database),
      bagOverflow: BagOverflowPref.load(storage),
    );
    addTearDown(stillTester.dispose);
    expect(stillTester.hasBagOverflowBadge, isTrue);

    stillTester.resetUnsigned();
    expect(stillTester.hasBagOverflowBadge, isFalse);
    expect(storage.getItem(BagOverflowPref.storageKeyFor('Tester')), '0');
    expect(stillTester.bagOverflow.identity, BagOverflowPref.unsignedIdentity);
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

    await tester.tap(find.text("I'd like that."));
    await tester.pumpAndSettle();

    expect(find.text(DialogueText.bagFull(1)), findsOne);
    expect(jsonEncode(controller.save.toJson()), before);
    expect(controller.save.dialogueFlags, isNot(contains('gift:QST-0011:seed')));
    expect(controller.save.inventory.any((stack) => stack.itemId == 'ITEM-0324'), isFalse);
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
