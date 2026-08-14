import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/ui/npc_panel.dart';
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

  testWidgets('the merchant pays for listening, once', (tester) async {
    final controller = buildController(database, seed: standing(merchantLocationId));
    addTearDown(controller.dispose);
    var closed = 0;

    await pumpPanel(
      tester,
      NpcPanel(controller: controller, npc: npcOf(merchantId), onClose: () => closed += 1),
    );
    expect(find.textContaining('tips about artisanry'), findsOne);
    expect(find.text('11,000 Artisanry XP'), findsOne);

    await tester.tap(find.text('Talk'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(closed, 0);
    expect(controller.save.claimedMerchantTipIds, [merchantId]);
    expect(getSkillProgress(controller.save, 'SKL-0012').level, greaterThan(1));

    // Coming back finds the advice already given, and nothing more to collect.
    // The key stands in for closing the panel and opening it again.
    final xpAfterFirst = getSkillProgress(controller.save, 'SKL-0012').xp;
    await pumpPanel(
      tester,
      NpcPanel(
        key: const ValueKey('second visit'),
        controller: controller,
        npc: npcOf(merchantId),
        onClose: () {},
      ),
    );
    expect(find.textContaining('already shared'), findsOne);
    await tester.tap(find.text('Talk'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(getSkillProgress(controller.save, 'SKL-0012').xp, xpAfterFirst);
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
    // The advice is still paid for on the way to the counter.
    expect(controller.save.claimedMerchantTipIds, [merchantId]);
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
        ],
        quests: const [QuestProgress(questId: 'QST-0002', status: 'active', progress: 0)],
      ),
    );
    addTearDown(controller.dispose);

    await pumpPanel(tester, NpcPanel(controller: controller, npc: npcOf(roseId), onClose: () {}));
    expect(find.textContaining("Progress: 5 / 5 Rabbit's Foot"), findsOne);
    expect(find.text('Gold: 1,500 / 1,000'), findsOne);

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

  testWidgets('a quest giver with no pitch is accepted straight from the list', (tester) async {
    final controller = buildController(database, seed: standing('LOC-0016'));
    addTearDown(controller.dispose);

    await pumpPanel(
      tester,
      NpcPanel(controller: controller, npc: npcOf('NPC-0001'), onClose: () {}),
    );
    expect(find.text('The Grand Feast'), findsOne);
    await tester.tap(find.text('Accept quest'));
    await tester.pump();

    expect(getQuestProgress(controller.save, 'QST-0001').status, 'active');
  });

  testWidgets('the Beggar at The Town asks for 25 gold', (tester) async {
    final controller = buildController(database, seed: standing('LOC-0002', gold: 40));
    addTearDown(controller.dispose);

    await pumpPanel(
      tester,
      NpcPanel(controller: controller, npc: npcOf('NPC-0011'), onClose: () {}),
    );
    await tester.tap(find.text('Donate 25 gold'));
    await tester.pump();
    expect(find.textContaining('coin purse'), findsOne);
    await tester.tap(find.text('Donate 25 gold'));
    await tester.pump();

    expect(getQuestProgress(controller.save, 'QST-0003').status, 'active');
    expect(controller.save.gold, 15);
  });
}
