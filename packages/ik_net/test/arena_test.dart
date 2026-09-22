import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase database;

  setUpAll(() {
    database = assertGameDatabaseShape(contentDatabaseJson());
  });

  test('search finds a stored player by name and ranked picks closest combat level', () {
    final harness = LocalMultiplayerBackend(storage: MemorySaveStorage());
    harness.ensureDemoWorld(database);
    final hero = harness.signUp('hero@example.com', 'Hero', 'secret').session!;
    harness.writeCloudSave(hero.userId, createNewSave(database, 1));

    final all = harness.listArenaOpponents(excludeUserId: hero.userId);
    expect(all.map((row) => row.username).toList(), containsAll(<String>['Bram', 'Kael', 'Mira']));
    expect(all.any((row) => row.userId == hero.userId), isFalse);

    expect(searchArenaOpponents(all, 'mi').single.username, 'Mira');
    expect(pickRankedOpponent(1, 13, all)?.username, 'Bram');
    expect(pickRankedOpponent(8, 13, all)?.username, 'Mira');
    expect(pickRankedOpponent(18, 18, all)?.username, 'Kael');

    final mira = harness.opponentSave(demoMiraId);
    expect(mira, isNotNull);
    expect(combatLevelOf(mira!), 8);
  });

  test('arena fights saved gear with live combat after a later cloud save', () {
    final harness = LocalMultiplayerBackend(storage: MemorySaveStorage());
    harness.ensureDemoWorld(database);
    final mira = harness.opponentSave(demoMiraId)!;
    final sword = equipStackToSlot(mira, weaponToolSlotId, 'ITEM-0128', 1);
    expect(harness.savePvpEquipment(demoMiraId, sword).ok, isTrue);

    final later = equipStackToSlot(
      mira.copyWith(
        raceId: 'RACE-0003',
        skills: [
          for (final skill in mira.skills)
            skill.skillId == mightSkillId || skill.skillId == vitalitySkillId
                ? skill.copyWith(level: 20)
                : skill,
        ],
      ),
      weaponToolSlotId,
      'ITEM-0102',
      1,
    );
    expect(harness.writeCloudSave(demoMiraId, later, force: true).ok, isTrue);
    final snapshot = harness.opponentSave(demoMiraId)!;
    expect(combatLevelOf(snapshot), 30);
    expect(snapshot.raceId, 'RACE-0003');
    expect(slotItemId(snapshot, weaponToolSlotId), 'ITEM-0128');

    final listed = harness.listArenaOpponents().firstWhere((row) => row.userId == demoMiraId);
    expect(listed.combatLevel, 30);
  });

  test('savePvpEquipment drops food and potions', () {
    final harness = LocalMultiplayerBackend(storage: MemorySaveStorage());
    harness.ensureDemoWorld(database);
    final hero = harness.signUp('hero@example.com', 'Hero', 'secret').session!;
    var save = equipStackToSlot(createNewSave(database, 1), foodSlotId, 'ITEM-0058', 2);
    save = equipStackToSlot(save, potionSlotId, 'ITEM-0073', 1);
    expect(harness.writeCloudSave(hero.userId, save).ok, isTrue);
    expect(harness.savePvpEquipment(hero.userId, save).ok, isTrue);

    final stored = harness.ownPvpSnapshot(hero.userId)!;
    expect(slotItemId(stored, foodSlotId), isNull);
    expect(slotItemId(stored, potionSlotId), isNull);
    expect(slotItemId(save, foodSlotId), 'ITEM-0058');
    expect(publicPvpEquipmentFromSave(save).any((slot) => slot.slotId == foodSlotId), isFalse);
    expect(publicPvpEquipmentFromSave(save).any((slot) => slot.slotId == potionSlotId), isFalse);
  });
}
