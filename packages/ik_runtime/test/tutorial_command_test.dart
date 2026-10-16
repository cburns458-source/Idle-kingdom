import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';
import 'package:test/test.dart';

/// Mirrors `applyGameCommand(..., { command: 'travel' })` in
/// `src/game/tutorial/tutorial.test.ts`: a refused command must not rewrite
/// Getting Started step progress. Dart has no `applyGameCommand`; [planTravel]
/// and [GameSession.travelTo] are the same command path.
void main() {
  late GameDatabase db;
  const now = 1760572800000; // 2026-10-16T00:00:00.000Z
  const farm = tutorialFarmLocationId;
  const copperMine = 'LOC-0003';

  setUpAll(() {
    db = assertGameDatabaseShape(contentDatabaseJson());
  });

  PlayerSave withoutFood(PlayerSave save) {
    return save.copyWith(
      inventory: save.inventory.where((stack) => !isEdibleItem(db, stack.itemId)).toList(),
      bank: save.bank.where((stack) => !isEdibleItem(db, stack.itemId)).toList(),
      equipment: EquipmentLoadout(
        slots: {
          for (final entry in save.equipment.slots.entries)
            if (entry.key != foodSlotId) entry.key: entry.value,
        },
      ),
    );
  }

  PlayerSave combatStepSave() {
    final assigned = assignRace(
      db,
      createNewSave(db, now).copyWith(currentLocationId: farm),
      'RACE-0001',
    );
    expect(assigned.ok, isTrue, reason: assigned.reason);
    var save = withoutFood(assigned.save!);
    save = save.copyWith(
      quests: [
        for (final quest in save.quests)
          if (quest.questId == tutorialQuestId)
            quest.copyWith(
              counters: {
                'step:QSTP-0013': 1,
                'step:QSTP-0014': 1,
                'step:QSTP-0015': 1,
                'step:QSTP-0016': 1,
              },
            )
          else
            quest,
      ],
    );
    return applyQuestStepUnlocks(db, save);
  }

  test('a refused travel command does not lose Getting Started step progress', () {
    final save = combatStepSave();
    expect(isStepLatched(save, tutorialQuestId, tutorialShowCookedStepId), isTrue);
    expect(getCurrentStepId(db, save, getQuest(db, tutorialQuestId)!), tutorialCombatStepId);

    final plan = planTravel(db, save, copperMine, mainMapId, now, () => 0);
    expect(plan, isA<TravelBlocked>());
    expect(isStepLatched(save, tutorialQuestId, tutorialShowCookedStepId), isTrue);
    expect(getCurrentStepId(db, save, getQuest(db, tutorialQuestId)!), tutorialCombatStepId);
    expect(save.currentLocationId, farm);

    final session = GameSession(
      db: db,
      repository: SaveRepository(storage: MemorySaveStorage(), clock: () => now),
      clock: () => now,
      random: () => 0,
    );
    session.boot();
    session.apply(save);
    final before = Map<String, Object?>.from(session.save.toJson());
    expect(session.travelTo(copperMine, mainMapId), isA<TravelBlocked>());
    expect(session.save.toJson(), before);
    expect(isStepLatched(session.save, tutorialQuestId, tutorialShowCookedStepId), isTrue);
    expect(
      getCurrentStepId(db, session.save, getQuest(db, tutorialQuestId)!),
      tutorialCombatStepId,
    );
    expect(session.save.currentLocationId, farm);
  });
}
