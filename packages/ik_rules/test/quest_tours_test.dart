import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

GameDatabase _db() => assertGameDatabaseShape(contentDatabaseJson());

PlayerSave _save(GameDatabase db, {required String locationId, num gold = 0}) {
  return createNewSave(db, 0).copyWith(currentLocationId: locationId, gold: gold);
}

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = _db();
  });

  test('the Beggar stands at the Town Bank', () {
    final beggar = db.npcs.firstWhere((row) => row.raw['NPC ID'] == 'NPC-0011');
    expect(beggar.raw['Location ID'], 'LOC-0034');
    expect(beggar.raw['Display Name'], 'Beggar');
  });

  test('the Lowly Beggar bribe grants the hood and a skill pick', () {
    var save = _save(db, locationId: 'LOC-0034', gold: 300);
    expect(acceptQuest(db, save, 'QST-0003').ok, isFalse);
    final donated = donateForQuest(db, save, 'QST-0003');
    expect(donated.ok, isTrue);
    save = donated.save!;
    expect(save.gold, 275);
    expect(getQuestProgress(save, 'QST-0003').status, 'inactive');
    final accepted = acceptQuest(db, save, 'QST-0003');
    expect(accepted.ok, isTrue);
    save = accepted.save!;
    expect(save.gold, 275);

    save = applyQuestTalkProgress(db, save, 'NPC-0011');
    save = applyQuestTalkProgress(db, save, 'NPC-0012');
    final bribed = bribeQuestNpc(db, save, 'QST-0003');
    expect(bribed.ok, isTrue);
    save = bribed.save!;
    expect(inventoryCount(save, 'ITEM-0299'), 1);

    save = save.copyWith(currentLocationId: 'LOC-0034');
    final completed = completeQuest(db, save, 'QST-0003');
    expect(completed.ok, isTrue);
    expect(completed.pendingSkillXp, 25000);
    expect(completed.save!.gold, 575);
    expect(isCosmeticUnlocked(completed.save!, 'COS-0002'), isTrue);
  });

  test('Harness essence unlocks on accept; Mages quarters wait for completion', () {
    var save = _save(db, locationId: 'LOC-0007');
    expect(activityVisibleForSave(db, save, 'ACT-0008'), isFalse);
    expect(
      specialProductionStationsVisibleAt(
        db,
        save,
        'LOC-0007',
      ).any((station) => station.facility.raw['Facility ID'] == 'FAC-0008'),
      isFalse,
    );

    final accepted = acceptQuest(db, save, 'QST-0005');
    expect(accepted.ok, isTrue);
    save = accepted.save!;
    expect(activityVisibleForSave(db, save, 'ACT-0008'), isTrue);
    expect(
      specialProductionStationsVisibleAt(
        db,
        save,
        'LOC-0007',
      ).any((station) => station.facility.raw['Facility ID'] == 'FAC-0008'),
      isFalse,
    );

    save = addItemToInventory(save, 'ITEM-0011', 10);
    save = applyQuestTalkProgress(db, save, 'NPC-0009');
    save = applyQuestTalkProgress(db, save, 'NPC-0004');
    final completed = completeQuest(db, save, 'QST-0005');
    expect(completed.ok, isTrue);
    expect(completed.rewards, contains('Unlocked Mages quarters'));
    expect(
      specialProductionStationsVisibleAt(
        db,
        completed.save!,
        'LOC-0007',
      ).any((station) => station.facility.raw['Facility ID'] == 'FAC-0008'),
      isTrue,
    );
  });

  test('arriving at the Citadel plaza starts Visiting the Citadel', () {
    final save = applyTravelArrival(db, _save(db, locationId: 'LOC-0002'), 'LOC-0028', 0);
    expect(getQuestProgress(save, 'QST-0004').status, 'active');
    expect(
      db.quests.firstWhere((row) => row['Quest ID'] == 'QST-0004')['Notes'],
      contains('AutoStart: LOC-0028'),
    );
  });

  test('Visiting the Citadel finishes after the visit stops', () {
    var save = applyTravelArrival(db, _save(db, locationId: 'LOC-0002'), 'LOC-0028', 0);
    save = applyTravelArrival(db, save, 'LOC-0029', 1);
    save = applyTravelArrival(db, save, 'LOC-0030', 2);
    save = applyTravelArrival(db, save, 'LOC-0035', 3);
    save = applyTravelArrival(db, save, 'LOC-0031', 4);
    expect(getQuestProgress(save, 'QST-0004').status, 'active');
    expect(completeQuest(db, save, 'QST-0004').ok, isFalse);
    save = applyTravelArrival(db, save, 'LOC-0032', 5);
    expect(getQuestProgress(save, 'QST-0004').status, 'completed');
    expect(save.gold, 1000);
  });

  test('Getting Started completes when Fennel sees the cooked potatoes', () {
    final fennel = db.npcs.firstWhere((row) => row.raw['NPC ID'] == 'NPC-0014');
    expect(fennel.raw['Location ID'], 'LOC-0001');

    NpcQuestBlock gettingStarted(PlayerSave save) => npcConversation(
      db,
      save,
      fennel,
      0,
    ).quests.singleWhere((quest) => quest.questId == 'QST-0006');

    var save = _save(db, locationId: 'LOC-0001');
    final accepted = acceptQuest(db, save, 'QST-0006');
    expect(accepted.ok, isTrue);
    save = accepted.save!;

    expect(gettingStarted(save).canTalk, isFalse);
    expect(gettingStarted(save).canTurnIn, isFalse);
    expect(gettingStarted(save).idlePrompt, contains('Take five potatoes from the field'));

    save = addItemToInventory(save, 'ITEM-0025', 5);
    expect(gettingStarted(save).canTalk, isTrue);
    expect(gettingStarted(save).talkLine, contains('You can cook them at the kitchen'));
    save = applyQuestTalkProgress(db, save, 'NPC-0014');
    expect(save.inventory.where((stack) => stack.itemId == 'ITEM-0025').single.quantity, 5);

    save = applyQuestVisitProgress(db, save, 'LOC-0023');
    save = applyQuestProcessProgress(db, save, 'RCP-0001', 5);
    save = addItemToInventory(save, 'ITEM-0058', 5);
    save = save.copyWith(currentLocationId: 'LOC-0001');
    expect(gettingStarted(save).talkLine, contains('sword and shield'));

    final advice = talkWithQuestNpc(db, save, 'NPC-0014');
    expect(advice.ok, isTrue);
    expect(getQuestProgress(advice.save!, 'QST-0006').status, 'active');
    expect(gettingStarted(advice.save!).talkLine, contains('Good luck on your adventure'));

    final finished = talkWithQuestNpc(db, advice.save!, 'NPC-0014');
    expect(finished.ok, isTrue);
    expect(getQuestProgress(finished.save!, 'QST-0006').status, 'completed');
    expect(isBookUnlocked(finished.save!, 'BOOK-0001'), isTrue);
    expect(
      finished.save!.inventory.where((stack) => stack.itemId == 'ITEM-0058').single.quantity,
      5,
    );
    // Fennel stays to teach Botany (QST-0011) after Getting Started.
    expect(
      npcsAtLocationForSave(db, finished.save!, 'LOC-0001', 0).map((npc) => npc.raw['NPC ID']),
      contains('NPC-0014'),
    );
  });

  test('Forged in Fire unlocks the forge; Going Deeper opens the shaft without kicking anyone', () {
    final merchant = db.npcs.firstWhere((row) => row.raw['NPC ID'] == 'NPC-0008');
    final helge = db.npcs.firstWhere((row) => row.raw['NPC ID'] == 'NPC-0015');
    expect(helge.raw['Location ID'], 'LOC-0038');

    var save = _save(db, locationId: 'LOC-0012').copyWith(
      skills: const [
        SkillProgress(skillId: 'SKL-0008', level: 35, xp: 0),
        SkillProgress(skillId: 'SKL-0011', level: 35, xp: 0),
        SkillProgress(skillId: 'SKL-0002', level: 60, xp: 0),
      ],
    );
    expect(npcConversation(db, _save(db, locationId: 'LOC-0012'), merchant, 0).quests, isEmpty);

    final pitched = npcConversation(db, save, merchant, 0);
    expect(pitched.quests.single.questId, 'QST-0007');
    expect(pitched.quests.single.pitchLine, contains('Could you help me get the old forge'));
    expect(pitched.quests.single.canAccept, isTrue);

    final accepted = acceptQuest(db, save, 'QST-0007');
    expect(accepted.ok, isTrue);
    save = accepted.save!;
    expect(save.unlockedLocationIds, contains('LOC-0038'));
    expect(specialProductionStationsVisibleAt(db, save, 'LOC-0038'), isEmpty);

    save = save.copyWith(currentLocationId: 'LOC-0038');
    save = applyQuestVisitProgress(db, save, 'LOC-0038');
    save = applyQuestTalkProgress(db, save, 'NPC-0015');
    save = addItemToInventory(save, 'ITEM-0077', 20);
    save = addItemToInventory(save, 'ITEM-0006', 100);
    save = applyQuestTalkProgress(db, save, 'NPC-0015');
    final forged = completeQuest(db, save, 'QST-0007');
    expect(forged.ok, isTrue);
    expect(forged.rewards.any((line) => line.contains('Smithing XP')), isTrue);
    expect(forged.rewards.any((line) => line.contains('Metallurgy XP')), isTrue);
    save = forged.save!;
    expect(specialProductionStationsVisibleAt(db, save, 'LOC-0038'), isNotEmpty);

    final deeper = acceptQuest(db, save, 'QST-0008');
    expect(deeper.ok, isTrue);
    save = deeper.save!;
    save = applyQuestTalkProgress(db, save, 'NPC-0015');
    expect(activityVisibleForSave(db, save, 'ACT-0044'), isTrue);
    expect(
      locationsForMapView(
        db,
        caveMapId,
        save.unlockedLocationIds,
        const <String>[],
        save.currentLocationId,
        save,
      ).map((row) => row.locationId),
      isNot(contains('LOC-0022')),
    );
    save = applyQuestVisitProgress(db, save, 'LOC-0011');
    save = applyQuestActionProgress(db, save, 'ACN-0177', 50);
    expect(
      locationsForMapView(
        db,
        caveMapId,
        save.unlockedLocationIds,
        const <String>[],
        save.currentLocationId,
        save,
      ).map((row) => row.locationId),
      contains('LOC-0022'),
    );
    expect(
      canTravelTo(db, 'LOC-0011', 'LOC-0022', caveMapId, save.unlockedLocationIds, save),
      isTrue,
    );

    final arrived = applyTravelArrival(db, save, 'LOC-0022', 0);
    expect(getQuestProgress(arrived, 'QST-0008').status, 'completed');
    expect(arrived.unlockedLocationIds, contains('LOC-0022'));
    expect(arrived.inventory.where((stack) => stack.itemId == 'ITEM-0313').single.quantity, 1);

    final stillInside = applyTravelArrival(db, _save(db, locationId: 'LOC-0022'), 'LOC-0022', 0);
    expect(stillInside.currentLocationId, 'LOC-0022');
    expect(
      locationsForMapView(
        db,
        caveMapId,
        stillInside.unlockedLocationIds,
        const <String>[],
        stillInside.currentLocationId,
        stillInside,
      ).map((row) => row.locationId),
      contains('LOC-0022'),
    );
    final leftHidden = applyTravelArrival(db, stillInside, 'LOC-0011', 0);
    expect(leftHidden.currentLocationId, 'LOC-0011');
    expect(leftHidden.unlockedLocationIds, isNot(contains('LOC-0022')));
    expect(
      locationsForMapView(
        db,
        caveMapId,
        leftHidden.unlockedLocationIds,
        const <String>[],
        leftHidden.currentLocationId,
        leftHidden,
      ).map((row) => row.locationId),
      isNot(contains('LOC-0022')),
    );
    expect(
      canTravelTo(
        db,
        'LOC-0011',
        'LOC-0022',
        caveMapId,
        leftHidden.unlockedLocationIds,
        leftHidden,
      ),
      isFalse,
    );
  });

  test('Going Deeper lists rubble counts on the journal and activity card', () {
    var save = _save(db, locationId: 'LOC-0011').copyWith(
      quests: const [QuestProgress(questId: 'QST-0008', status: 'active', progress: 0)],
    );
    save = applyQuestTalkProgress(db, save, 'NPC-0015');
    final quest = db.quests.firstWhere((row) => row['Quest ID'] == 'QST-0008');
    expect(
      questStepJournal(db, save, quest).map((step) => step.label),
      contains('Clear a rubble pile 0 / 50'),
    );
    expect(questActionProgressForActivity(db, save, 'ACT-0044').map((line) => line.caption), [
      'Clear a rubble pile 0 / 50',
    ]);

    save = applyQuestActionProgress(db, save, 'ACN-0177', 12);
    expect(questActionProgressForActivity(db, save, 'ACT-0044').map((line) => line.caption), [
      'Clear a rubble pile 12 / 50',
    ]);
    expect(
      questStepJournal(db, save, quest).map((step) => step.label),
      contains('Clear a rubble pile 12 / 50'),
    );

    save = applyQuestActionProgress(db, save, 'ACN-0177', 88);
    expect(questActionProgressForActivity(db, save, 'ACT-0044').map((line) => line.caption), [
      'Clear a rubble pile 50 / 50',
    ]);
    expect(
      questStepJournal(db, save, quest).map((step) => step.label),
      contains('Clear a rubble pile 50 / 50'),
    );
  });

  test('Through the Thicket is offered by the Old Forester and does not auto-start', () {
    expect(
      db.npcs.firstWhere((row) => row.raw['NPC ID'] == 'NPC-0017').raw['Display Name'],
      'Old Forester',
    );
    final arrived = applyTravelArrival(db, _save(db, locationId: 'LOC-0002'), 'LOC-0040', 0);
    expect(getQuestProgress(arrived, 'QST-0010').status, 'inactive');
    expect(acceptQuest(db, arrived, 'QST-0010').ok, isFalse);

    var ready = raiseSkillToMinimumLevel(arrived, db, 'SKL-0006', 40).save;
    ready = raiseSkillToMinimumLevel(ready, db, 'SKL-0014', 35).save;
    final accepted = acceptQuestFromNpc(db, ready, 'QST-0010');
    expect(accepted.ok, isTrue);
    expect(
      accepted.message,
      'Thank you. Start with clearing some vines here to gain access to the deeper parts of the woods.',
    );
    expect(questTalkLine(db, 'QST-0010', 'NPC-0017', accepted.save), accepted.message);
    final save = accepted.save!;
    expect(
      questLog(
        db,
        save,
      ).singleWhere((row) => row.questId == 'QST-0010').steps.map((step) => step.label),
      containsAll(<String>['Clear fifty vines on the Forest Path', 'Chop vines 0 / 50']),
    );
    expect(questActionProgressForActivity(db, save, 'ACT-0048').map((line) => line.caption), [
      'Chop vines 0 / 50',
    ]);
    final quest = db.quests.firstWhere((row) => row['Quest ID'] == 'QST-0010');
    expect(getCurrentStepId(db, save, quest), 'QSTP-0025');
  });

  test('Through the Thicket opens each grove after ten vines and finishes on the last talk', () {
    var save = raiseSkillToMinimumLevel(_save(db, locationId: 'LOC-0040'), db, 'SKL-0006', 40).save;
    save = raiseSkillToMinimumLevel(save, db, 'SKL-0014', 35).save;
    final accepted = acceptQuest(db, save, 'QST-0010');
    expect(accepted.ok, isTrue);
    save = accepted.save!;
    final quest = db.quests.firstWhere((row) => row['Quest ID'] == 'QST-0010');

    expect(activityVisibleForSave(db, save, 'ACT-0077'), isFalse);
    save = applyQuestActionProgress(db, save, 'ACN-0179', 49);
    expect(save.unlockedLocationIds, isNot(contains(smallClearingId)));
    expect(
      getQuestProgress(applyQuestAutoCompleteOnAction(db, save).save, 'QST-0010').status,
      'active',
    );
    save = applyQuestActionProgress(db, save, 'ACN-0179', 1);
    expect(save.unlockedLocationIds, contains(smallClearingId));
    expect(getQuestProgress(save, 'QST-0010').status, 'active');
    expect(questActionProgressForActivity(db, save, 'ACT-0048'), isEmpty);
    expect(getCurrentStepId(db, save, quest), 'QSTP-0026');
    expect(activityVisibleForSave(db, save, 'ACT-0077'), isFalse);
    expect(
      questTalkLine(db, 'QST-0010', 'NPC-0017', save),
      "You'll need to clear more vines to get further. Keep clearing vines until you reach the Old Ent Grove.",
    );

    save = talkWithQuestNpc(db, save, 'NPC-0017').save!;
    expect(activityVisibleForSave(db, save, 'ACT-0077'), isTrue);
    save = applyQuestActionProgress(db, save, 'ACN-0179', 10);
    expect(save.unlockedLocationIds, contains(starlightGladeId));
    expect(activityVisibleForSave(db, save, 'ACT-0077'), isFalse);

    save = applyQuestActionProgress(db, save, 'ACN-0179', 10);
    expect(save.unlockedLocationIds, contains(mirrorLakeId));
    save = applyQuestActionProgress(db, save, 'ACN-0179', 10);
    expect(save.unlockedLocationIds, contains(oldEntGroveId));
    save = talkWithQuestNpc(db, save, 'NPC-0017').save!;
    expect(activityVisibleForSave(db, save, 'ACT-0080'), isTrue);

    save = applyQuestProcessProgress(db, save, 'RCP-0071', 4);
    expect(getCurrentStepId(db, save, quest), 'QSTP-0032');
    save = addItemToInventory(save, 'ITEM-0405', 4);
    expect(
      applyQuestLocationProgressResult(db, save, smallClearingId).message,
      forestOfferingPlacedMessage,
    );
    final silent = applyQuestLocationProgressResult(
      db,
      save.copyWith(inventory: const <InventoryStack>[]),
      smallClearingId,
    );
    expect(silent.message, isNull);
    expect(hasQuestFlag(silent.save, 'QST-0010', 'visit:$smallClearingId'), isFalse);

    save = applyQuestLocationProgressResult(db, save, smallClearingId).save;
    expect(inventoryCount(save, 'ITEM-0405'), 3);
    save = applyQuestLocationProgressResult(db, save, starlightGladeId).save;
    save = applyQuestLocationProgressResult(db, save, mirrorLakeId).save;
    save = applyQuestLocationProgressResult(db, save, oldEntGroveId).save;
    expect(inventoryCount(save, 'ITEM-0405'), 0);

    final finished = talkWithQuestNpc(db, save, 'NPC-0017');
    expect(finished.ok, isTrue);
    expect(getQuestProgress(finished.save!, 'QST-0010').status, 'completed');
    expect(inventoryCount(finished.save!, 'ITEM-0406'), 1);
    expect(activityVisibleForSave(db, finished.save!, 'ACT-0080'), isFalse);
    expect(
      locationsForMapView(
        db,
        forestMapId,
        finished.save!.unlockedLocationIds,
        const <String>[],
        finished.save!.currentLocationId,
        finished.save,
      ).map((row) => row.locationId),
      containsAll(<String>[smallClearingId, starlightGladeId, mirrorLakeId, oldEntGroveId]),
    );
    expect(
      canTravelTo(
        db,
        'LOC-0040',
        oldEntGroveId,
        forestMapId,
        finished.save!.unlockedLocationIds,
        finished.save,
      ),
      isTrue,
    );

    final completer = createNewSave(db, 0).copyWith(
      quests: const <QuestProgress>[
        QuestProgress(questId: 'QST-0010', status: 'completed', progress: 0),
      ],
    );
    expect(
      locationsForMapView(
        db,
        forestMapId,
        completer.unlockedLocationIds,
        const <String>[],
        completer.currentLocationId,
        completer,
      ).map((row) => row.locationId),
      containsAll(<String>[smallClearingId, starlightGladeId, mirrorLakeId, oldEntGroveId]),
    );
    expect(
      acceptQuest(db, completer.copyWith(currentLocationId: 'LOC-0040'), 'QST-0010').ok,
      isFalse,
    );

    final vines = db.actions.firstWhere((row) => row.actionId == 'ACN-0179');
    final oak = db.actions.firstWhere((row) => row.actionId == 'ACN-0047');
    var geared = raiseSkillToMinimumLevel(createNewSave(db, 0), db, 'SKL-0006', 40).save;
    geared = equipStackToSlot(geared, weaponToolSlotId, 'ITEM-0406', 1);
    expect(equippedActionTimeReductionPercentForAction(db, geared, vines), 24);
    expect(equippedActionTimeReductionPercentForAction(db, geared, oak), 11);
    expect(gatheringDurationMs(db, geared, vines), closeTo(55 * (1 - 24 / 100) * 1000, 0.01));
  });

  test('Green Thumb waits for Getting Started, hides from the log, and finishes after compost planting', () {
    final quest = getQuest(db, 'QST-0011')!;
    expect(quest['Display Name'], 'Green Thumb');
    expect(hideFromQuestLog(quest), isTrue);
    final parsed = parseStructuredObjectives(quest);
    expect(parsed.requiresQuestIds, <String>['QST-0006']);
    expect(parsed.autoCompleteOnTalk, isTrue);
    expect(parsed.autoCompleteOnPlant, isFalse);
    expect(parsed.rewardItems, hasLength(2));
    expect(parsed.rewardItems.first.targetId, 'ITEM-0324');
    expect(parsed.rewardItems.first.quantity, 3);
    expect(parsed.rewardItems.last.targetId, 'ITEM-0339');
    expect(parsed.rewardItems.last.quantity, 3);

    var save = _save(
      db,
      locationId: 'LOC-0001',
    ).copyWith(inventory: const [InventoryStack(itemId: 'ITEM-0324', quantity: 1)]);
    save = applyQuestAutoStartOnSeed(db, save);
    expect(getQuestProgress(save, 'QST-0011').status, 'inactive');
    expect(questLog(db, save).any((row) => row.questId == 'QST-0011'), isFalse);

    save = save.copyWith(
      quests: const [QuestProgress(questId: 'QST-0006', status: 'completed', progress: 1)],
    );
    save = applyQuestAutoStartOnSeed(db, save);
    expect(getQuestProgress(save, 'QST-0011').status, 'active');
    expect(questLog(db, save).any((row) => row.questId == 'QST-0011'), isFalse);
    expect(farmBotanyUnlocked(save), isFalse);

    final firstTalk = talkWithQuestNpc(db, save, 'NPC-0014');
    expect(firstTalk.ok, isTrue);
    save = firstTalk.save!;
    expect(inventoryCount(save, 'ITEM-0324'), 2);
    expect(farmBotanyUnlocked(save), isTrue);

    save = addItemToInventory(save, 'ITEM-0377', 1);
    save = applyQuestActionProgress(db, save, 'ACN-0199', 1);
    final compostTalk = talkWithQuestNpc(db, save, 'NPC-0014');
    expect(compostTalk.ok, isTrue);
    save = compostTalk.save!;
    expect(getQuestProgress(save, 'QST-0011').status, 'active');

    final refused = plantBotanySelection(db, save, const ['ITEM-0324'], nowMs: 0);
    expect(refused.ok, isFalse);
    expect(refused.reason, contains('compost'));

    final planted = plantBotanySelection(
      db,
      save,
      const ['ITEM-0324'],
      nowMs: 0,
      usedCompost: true,
    );
    expect(planted.ok, isTrue);
    save = planted.save!;
    expect(getQuestProgress(save, 'QST-0011').status, 'active');

    final finished = talkWithQuestNpc(db, save, 'NPC-0014');
    expect(finished.ok, isTrue);
    expect(finished.message, contains('favour you a little more'));
    expect(getQuestProgress(finished.save!, 'QST-0011').status, 'completed');
    expect(isBookUnlocked(finished.save!, 'BOOK-0002'), isTrue);
    expect(inventoryCount(finished.save!, 'ITEM-0324'), 4);
    expect(inventoryCount(finished.save!, 'ITEM-0339'), 3);
    expect(
      botanyCollectChancePercent(finished.save!, 'LOC-0001', 1, 1),
      botanySuccessChancePercent(1, 1) + 10,
    );
    expect(
      botanyCollectChancePercent(finished.save!, 'LOC-0031', 1, 1),
      botanySuccessChancePercent(1, 1),
    );
  });

  test('wardrobe lists The Undying in the Titles slot', () {
    final save = createNewSave(db, 0);
    final tabs = wardrobeSlotTabs(db);
    expect(tabs.map((tab) => tab.slotId), contains('CSLOT-0003'));
    final titles = wardrobeSlotView(db, save, 'CSLOT-0003');
    expect(titles!.tiles.map((tile) => tile.name), ['The Undying']);
    expect(titles.tiles.single.equipped, isTrue);
  });
}
