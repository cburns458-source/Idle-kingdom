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

  test('the Missing Purse bribe grants the hood and a skill pick', () {
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

    save = applyQuestTalkProgress(db, save, 'NPC-0007');
    save = applyQuestTalkProgress(db, save, 'NPC-0012');
    final bribed = bribeQuestNpc(db, save, 'QST-0003');
    expect(bribed.ok, isTrue);
    save = bribed.save!;
    expect(inventoryCount(save, 'ITEM-0299'), 1);

    save = save.copyWith(currentLocationId: 'LOC-0034');
    final completed = completeQuest(db, save, 'QST-0003');
    expect(completed.ok, isTrue);
    expect(completed.pendingSkillXp, 2500);
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
      db.quests.firstWhere((row) => row.raw['Quest ID'] == 'QST-0004').raw['Notes'],
      contains('AutoStart: LOC-0028'),
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
