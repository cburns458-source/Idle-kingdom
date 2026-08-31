import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

PlayerSave _withTotalLevel(PlayerSave save, num target) {
  final current = totalLevel(save);
  final bump = target - current;
  if (bump <= 0) return save;
  final first = save.skills.first;
  return save.copyWith(
    skills: <SkillProgress>[
      first.copyWith(level: first.level + bump),
      ...save.skills.skip(1),
    ],
  );
}

PlayerSave _payFor(PlayerSave save, String raceId) {
  final cost = raceChangeCostFor(raceId)!;
  var next = save.copyWith(gold: save.gold + cost.gold);
  for (final item in cost.items) {
    next = addItemToInventory(next, item.itemId, item.quantity);
  }
  return next;
}

void main() {
  final db = assertGameDatabaseShape(contentDatabaseJson());
  const nowMs = 1788134400000; // 2026-08-31

  test('Vesper stays hidden until total level 500', () {
    final assigned = assignRace(db, createNewSave(db, nowMs), 'RACE-0001');
    expect(assigned.ok, isTrue);
    final atHall = assigned.save!.copyWith(currentLocationId: 'LOC-0015');
    expect(
      npcsAtLocationForSave(db, atHall, 'LOC-0015').map((npc) => npc.npcId),
      isNot(contains(vesperId)),
    );
    expect(miniQuestLog(db, atHall, nowMs), isEmpty);

    final ready = _withTotalLevel(atHall, raceChangeTotalLevel);
    expect(
      npcsAtLocationForSave(db, ready, 'LOC-0015').map((npc) => npc.npcId),
      contains(vesperId),
    );
    expect(miniQuestLog(db, ready, nowMs).map((row) => row.questId), [raceChangeMiniquestId]);
  });

  test('keeps A Change of Skin out of the quest journal', () {
    expect(
      questLog(db, createNewSave(db, nowMs)).any((row) => row.questId == raceChangeMiniquestId),
      isFalse,
    );
  });

  test('changes race for mid-level goods and starts a weekly cooldown', () {
    final assigned = assignRace(db, createNewSave(db, nowMs), 'RACE-0001');
    final ready = _payFor(
      _withTotalLevel(assigned.save!.copyWith(currentLocationId: 'LOC-0015'), raceChangeTotalLevel),
      'RACE-0006',
    );
    final offer = raceChangeOffer(db, ready, nowMs);
    expect(offer.ready, isTrue);
    expect(offer.warning.toLowerCase(), isNot(contains('starter')));

    final changed = changeRaceAtNpc(db, ready, 'RACE-0006', nowMs);
    expect(changed.ok, isTrue);
    expect(changed.save!.raceId, 'RACE-0006');
    expect(changed.message!.toLowerCase(), isNot(contains('starter')));

    final again = changeRaceAtNpc(
      db,
      _payFor(changed.save!, 'RACE-0002'),
      'RACE-0002',
      nowMs + 1000,
    );
    expect(again.ok, isFalse);
    expect(again.reason, contains('Come back in'));

    final later = changeRaceAtNpc(
      db,
      _payFor(changed.save!, 'RACE-0002'),
      'RACE-0002',
      nowMs + 7 * 24 * 60 * 60 * 1000,
    );
    expect(later.ok, isTrue);
    expect(later.save!.raceId, 'RACE-0002');
  });
}
