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

  test('Delve stays hidden until Wizard Studies is accepted', () {
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

  test('Getting Started completes when Fennel sees the cooked potatoes', () {
    final fennel = db.npcs.firstWhere((row) => row.raw['NPC ID'] == 'NPC-0014');
    expect(fennel.raw['Location ID'], 'LOC-0001');

    var save = _save(db, locationId: 'LOC-0001');
    final accepted = acceptQuest(db, save, 'QST-0006');
    expect(accepted.ok, isTrue);
    save = accepted.save!;

    expect(npcConversation(db, save, fennel).quests.single.canTalk, isTrue);
    expect(npcConversation(db, save, fennel).quests.single.canTurnIn, isFalse);
    save = applyQuestTalkProgress(db, save, 'NPC-0014');
    expect(npcConversation(db, save, fennel).quests.single.canTalk, isFalse);

    save = addItemToInventory(save, 'ITEM-0025', 5);
    expect(npcConversation(db, save, fennel).quests.single.canTalk, isTrue);
    expect(npcConversation(db, save, fennel).quests.single.talkLine, contains('kitchen in town'));
    save = applyQuestTalkProgress(db, save, 'NPC-0014');
    expect(save.inventory.where((stack) => stack.itemId == 'ITEM-0025').single.quantity, 5);

    save = applyQuestVisitProgress(db, save, 'LOC-0023');
    save = applyQuestProcessProgress(db, save, 'RCP-0001', 5);
    save = addItemToInventory(save, 'ITEM-0058', 5);
    save = save.copyWith(currentLocationId: 'LOC-0001');
    expect(npcConversation(db, save, fennel).quests.single.talkLine, contains('sword and shield'));

    final advice = talkWithQuestNpc(db, save, 'NPC-0014');
    expect(advice.ok, isTrue);
    expect(getQuestProgress(advice.save!, 'QST-0006').status, 'active');
    expect(
      npcConversation(db, advice.save!, fennel).quests.single.talkLine,
      contains('Good luck on your adventure'),
    );

    final finished = talkWithQuestNpc(db, advice.save!, 'NPC-0014');
    expect(finished.ok, isTrue);
    expect(getQuestProgress(finished.save!, 'QST-0006').status, 'completed');
    expect(
      finished.save!.inventory.where((stack) => stack.itemId == 'ITEM-0058').single.quantity,
      5,
    );
    expect(npcsAtLocationForSave(db, finished.save!, 'LOC-0001'), isEmpty);
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
    expect(npcConversation(db, _save(db, locationId: 'LOC-0012'), merchant).quests, isEmpty);

    final pitched = npcConversation(db, save, merchant);
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
    save = applyQuestActionProgress(db, save, 'ACN-0177', 100);
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
      contains('Clear a rubble pile 0 / 100'),
    );
    expect(questActionProgressForActivity(db, save, 'ACT-0044').map((line) => line.caption), [
      'Clear a rubble pile 0 / 100',
    ]);

    save = applyQuestActionProgress(db, save, 'ACN-0177', 12);
    expect(questActionProgressForActivity(db, save, 'ACT-0044').map((line) => line.caption), [
      'Clear a rubble pile 12 / 100',
    ]);
    expect(
      questStepJournal(db, save, quest).map((step) => step.label),
      contains('Clear a rubble pile 12 / 100'),
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
