import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/ui/npc_panel.dart';
import 'package:idle_kingdoms/src/ui/social_bits.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  /// The general store merchant, the two mentors, Rose, and the king.
  const merchantId = 'NPC-0007';
  const merchantLocationId = 'LOC-0024';
  const masterDwarfId = 'NPC-0003';
  const forgeLocationId = 'LOC-0006';
  const roseId = 'NPC-0005';
  const kitchenLocationId = 'LOC-0023';
  const rabbitsFootId = 'ITEM-0038';
  const fernleafId = 'ITEM-0031';

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  NpcRow npcOf(String npcId) {
    return database.launch.npcs.firstWhere((row) => row.raw['NPC ID'] == npcId);
  }

  PlayerSave standing(
    String locationId, {
    num gold = 0,
    List<InventoryStack> inventory = const [],
    List<QuestProgress> quests = const [],
  }) {
    return startedCharacter(database)
        .copyWith(currentLocationId: locationId, gold: gold, inventory: inventory, quests: quests);
  }

  testWidgets('the merchant names Quill’s stop instead of teaching artisanry', (tester) async {
    final controller = buildController(database, seed: standing(merchantLocationId));
    addTearDown(controller.dispose);
    var closed = 0;
    final artisanryXp = getSkillProgress(controller.save, 'SKL-0012').xp;

    await pumpPanel(
      tester,
      NpcPanel(controller: controller, npc: npcOf(merchantId), onClose: () => closed += 1),
    );
    expect(find.textContaining('tips about artisanry'), findsNothing);
    expect(find.text('Ask about Quill'), findsOne);

    await tester.tap(find.text('Ask about Quill'));
    await tester.pump();
    expect(find.textContaining('Last I heard, Quill was at the'), findsOne);
    final portrait = tester.getRect(find.byType(SocialPortrait));
    expect(portrait.width, 68);
    expect(portrait.height, 68);

    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(closed, 0);
    expect(controller.save.claimedMerchantTipIds, isEmpty);
    expect(getSkillProgress(controller.save, 'SKL-0012').xp, artisanryXp);
  });

  testWidgets('the merchant hands the player on to their counter', (tester) async {
    final controller = buildController(database, seed: standing(merchantLocationId));
    addTearDown(controller.dispose);
    String? opened;

    await pumpPanel(
      tester,
      NpcPanel(
        controller: controller,
        npc: npcOf(merchantId),
        onClose: () {},
        onOpenShop: (shopId) => opened = shopId,
      ),
    );
    await tester.tap(find.text('Browse the shop'));
    await tester.pump();

    expect(opened, 'SHP-0001');
    expect(controller.save.claimedMerchantTipIds, isEmpty);
  });

  testWidgets('the mining merchant says where the Master Dwarf is today', (tester) async {
    final controller = buildController(database, seed: standing('LOC-0012'));
    addTearDown(controller.dispose);

    await pumpPanel(
      tester,
      NpcPanel(controller: controller, npc: npcOf('NPC-0008'), onClose: () {}),
    );
    expect(find.text('Ask where the Master Dwarf is'), findsOne);

    await tester.tap(find.text('Ask where the Master Dwarf is'));
    await tester.pump();

    expect(find.textContaining('The Master Dwarf is at the'), findsOne);
    expect(find.textContaining('today.'), findsOne);
  });

  testWidgets('the mentor unlocks projects and then says so', (tester) async {
    final controller = buildController(database, seed: standing(forgeLocationId));
    addTearDown(controller.dispose);

    await pumpPanel(
      tester,
      NpcPanel(controller: controller, npc: npcOf(masterDwarfId), onClose: () {}),
    );
    await tester.tap(find.text('Learn Smithing projects'));
    await tester.pump();

    expect(controller.save.unlockedNpcIds, contains(masterDwarfId));
    expect(controller.message, 'The Master Dwarf unlocks all Smithing projects.');
    expect(find.text('Smithing projects are unlocked.'), findsOne);
  });

  testWidgets('Quill teaches bows and quivers in his own words', (tester) async {
    final today = quillLocationId(testStartMs);
    final controller = buildController(database, seed: standing(today));
    addTearDown(controller.dispose);

    await pumpPanel(
      tester,
      NpcPanel(controller: controller, npc: npcOf('NPC-0002'), onClose: () {}),
    );
    expect(find.text('Quill'), findsOne);
    expect(find.text('A master hunter.'), findsOne);
    expect(find.text('Ask about hunting'), findsOne);

    await tester.tap(find.text('Ask about hunting'));
    await tester.pump();
    expect(find.textContaining('combat experience'), findsOne);
    expect(find.textContaining('quiver'), findsOne);

    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(controller.save.unlockedNpcIds, contains('NPC-0002'));
    expect(controller.message, 'Quill shows you how to make bows and quivers.');
    expect(find.text('You know how to make bows and quivers.'), findsOne);
  });

  testWidgets('Rose pitches her shop, and declining leaves the quest alone', (tester) async {
    final controller = buildController(database, seed: standing(kitchenLocationId));
    addTearDown(controller.dispose);

    await pumpPanel(tester, NpcPanel(controller: controller, npc: npcOf(roseId), onClose: () {}));
    await tester.tap(find.text('Start quest: Help the aspiring apothecary'));
    await tester.pump();
    expect(find.textContaining('alchemy shop'), findsOne);

    await tester.tap(find.text('Not now'));
    await tester.pump();

    expect(controller.save.quests, isEmpty);
    // The quest is still on offer from her list, pitch and all.
    await tester.tap(find.text('Start quest: Help the aspiring apothecary'));
    await tester.pump();
    expect(find.textContaining('alchemy shop'), findsOne);

    await tester.tap(find.text('Start quest: Help the aspiring apothecary'));
    await tester.pump();
    expect(getQuestProgress(controller.save, 'QST-0002').status, 'active');
    expect(controller.message, 'Accepted: Help the aspiring apothecary.');
  });

  testWidgets('an active quest shows its progress and pays out on turn-in', (tester) async {
    final controller = buildController(
      database,
      seed: standing(
        kitchenLocationId,
        gold: 1500,
        inventory: const [
          InventoryStack(itemId: rabbitsFootId, quantity: 5),
          InventoryStack(itemId: fernleafId, quantity: 5),
          InventoryStack(itemId: 'ITEM-0028', quantity: 5),
          InventoryStack(itemId: 'ITEM-0042', quantity: 5),
        ],
        quests: const [QuestProgress(questId: 'QST-0002', status: 'active', progress: 0)],
      ),
    );
    addTearDown(controller.dispose);

    await pumpPanel(tester, NpcPanel(controller: controller, npc: npcOf(roseId), onClose: () {}));
    expect(find.text('Talk'), findsOne);
    expect(find.textContaining("Progress: 5 / 5 Rabbit's Foot"), findsNothing);
    expect(find.text('Gold: 1,500 / 1,000'), findsNothing);

    await tester.tap(find.text('Talk'));
    await tester.pump();
    expect(find.textContaining('wild berries'), findsOne);
    await tester.tap(find.text('Continue'));
    await tester.pump();

    await tester.tap(find.text('Turn in'));
    await tester.pumpAndSettle();

    expect(controller.save.gold, 500);
    expect(controller.save.unlockedLocationIds, contains('LOC-0026'));
    // The payout is listed before it is collected.
    expect(find.textContaining('Alchemy XP'), findsOne);
    await tester.tap(find.text('Collect'));
    await tester.pumpAndSettle();

    expect(find.text("Completed — Rose's Apothecary is open on the Town Map."), findsOne);
  });

  testWidgets('the King pitches the feast, then asks for help after accept', (tester) async {
    final controller = buildController(database, seed: standing('LOC-0016'));
    addTearDown(controller.dispose);

    await pumpPanel(
      tester,
      NpcPanel(controller: controller, npc: npcOf('NPC-0001'), onClose: () {}),
    );
    expect(find.textContaining('My cooks have fled'), findsOne);
    await tester.tap(find.text('Start quest: The Grand Feast').last);
    await tester.pump();
    await tester.tap(find.text('Start quest: The Grand Feast'));
    await tester.pump();

    expect(getQuestProgress(controller.save, 'QST-0001').status, 'active');
    expect(find.text('Talk'), findsOne);
    expect(find.textContaining('baked potatoes'), findsNothing);
  });

  testWidgets('the Beggar at The Town asks for 25 gold', (tester) async {
    final controller = buildController(database, seed: standing('LOC-0034', gold: 40));
    addTearDown(controller.dispose);

    await pumpPanel(
      tester,
      NpcPanel(controller: controller, npc: npcOf('NPC-0011'), onClose: () {}),
    );
    expect(find.text('Quest Giver'), findsNothing);
    await tester.tap(find.text('Donate 25 gold'));
    await tester.pump();

    expect(getQuestProgress(controller.save, 'QST-0003').status, 'inactive');
    expect(controller.save.gold, 15);
    expect(find.text('Start the quest Lowly Beggar?'), findsOne);

    await pumpPanel(
      tester,
      NpcPanel(
        key: const ValueKey('after donate'),
        controller: controller,
        npc: npcOf('NPC-0011'),
        onClose: () {},
      ),
    );
    expect(find.text('Donate 25 gold'), findsNothing);
    expect(find.text('Start the quest Lowly Beggar?'), findsWidgets);
    await tester.tap(find.text('Start the quest Lowly Beggar?').last);
    await tester.pump();
    await tester.tap(find.text('Start the quest Lowly Beggar?'));
    await tester.pump();

    expect(getQuestProgress(controller.save, 'QST-0003').status, 'active');
    expect(controller.save.gold, 15);
    expect(find.text('Talk'), findsOne);
    expect(find.textContaining('Donate 25 gold, then recover'), findsNothing);

    await tester.tap(find.text('Talk'));
    await tester.pump();
    expect(find.textContaining('around town'), findsOne);
    expect(find.textContaining('barracks'), findsNothing);
  });

  testWidgets('Fennel welcomes a new farmhand, then teaches in stages', (tester) async {
    final controller = buildController(database, seed: standing('LOC-0001'));
    addTearDown(controller.dispose);

    await pumpPanel(
      tester,
      NpcPanel(controller: controller, npc: npcOf('NPC-0014'), onClose: () {}),
    );
    expect(find.textContaining('Gather five potatoes'), findsOne);
    await tester.tap(find.text('Start quest: Getting Started').last);
    await tester.pump();
    await tester.tap(find.text('Start quest: Getting Started'));
    await tester.pump();

    expect(getQuestProgress(controller.save, 'QST-0006').status, 'active');
    expect(find.text('Talk'), findsOne);
    expect(find.text('Turn in'), findsNothing);

    await tester.tap(find.text('Talk'));
    await tester.pump();
    expect(find.textContaining('five potatoes from the field'), findsOne);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Talk'), findsNothing);

    controller.commit(addItemToInventory(controller.save, 'ITEM-0025', 5));
    await pumpPanel(
      tester,
      NpcPanel(
        key: const ValueKey('show potatoes'),
        controller: controller,
        npc: npcOf('NPC-0014'),
        onClose: () {},
      ),
    );
    await tester.tap(find.text('Talk'));
    await tester.pump();
    expect(find.textContaining('kitchen in town'), findsOne);
    expect(
      controller.save.inventory.where((stack) => stack.itemId == 'ITEM-0025').single.quantity,
      5,
    );
  });
}
