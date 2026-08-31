import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

GameDatabase _db() => filterLaunchContent(assertGameDatabaseShape(contentDatabaseJson()));

PlayerSave _atTemple(GameDatabase db, {num hp = 400}) {
  return createNewSave(db, 0).copyWith(currentLocationId: 'LOC-0036', currentHp: hp);
}

PlayerSave _withHands(PlayerSave save, {String? weaponId, String? offhandId}) {
  var next = save;
  if (weaponId != null) next = equipStackToSlot(next, weaponToolSlotId, weaponId, 1);
  if (offhandId != null) next = equipStackToSlot(next, offhandSlotId, offhandId, 1);
  return next;
}

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = _db();
  });

  test('Temple is a main-map Launch node with monk training and a blessing', () {
    final location = db.locations.firstWhere((row) => row.locationId == 'LOC-0036');
    expect(location.raw['Display Name'], 'Temple');
    expect(location.raw['Map ID'], mainMapId);
    expect(layoutForMap(mainMapId).containsKey('LOC-0036'), isTrue);
    expect(canTravelTo(db, 'LOC-0002', 'LOC-0036', mainMapId), isTrue);
    expect(locationHasBlessing(location), isTrue);

    final activities = db.activities.where((row) => row.raw['Location ID'] == 'LOC-0036');
    expect(activities.map((row) => row.raw['Contextual Name']), [
      'Train with the monks',
      'Pick weeds',
    ]);
    expect(db.activities.any((row) => row.activityId == 'ACT-0036'), isFalse);
  });

  test('Pick weeds rolls augur weed or moonblossom with empty hands', () {
    final activity = db.activities.firstWhere((row) => row.activityId == 'ACT-0039');
    expect(activity.raw['Contextual Name'], 'Pick weeds');
    expect(activity.poolId, 'POOL-0029');

    final pool = db.poolEntries.where((row) => row.raw['Pool ID'] == 'POOL-0029').toList();
    expect(pool, hasLength(2));
    expect(
      pool.map((row) => '${row.raw['Action ID']}:${row.raw['Weight']}'),
      containsAll(<String>['ACN-0109:90', 'ACN-0110:10']),
    );

    final augur = db.actions.firstWhere((row) => row.actionId == 'ACN-0109');
    expect(augur.displayName, 'Gather augur weed');
    expect(augur.relevantSkillId, 'SKL-0004');
    expect(augur.proficiencyLevel, 50);
    expect(augur.xpReward, 50000);
    expect(augur.baseDurationSeconds, 360);

    final moonblossom = db.actions.firstWhere((row) => row.actionId == 'ACN-0110');
    expect(moonblossom.displayName, 'Gather moonblossom');
    expect(moonblossom.proficiencyLevel, 70);
    expect(moonblossom.xpReward, 75000);
    expect(moonblossom.baseDurationSeconds, 540);

    expect(db.actions.any((row) => row.actionId == 'ACN-0174'), isFalse);

    var save = _withHands(_atTemple(db), weaponId: 'ITEM-0100', offhandId: 'ITEM-0145');
    final started = requestActivityStart(db, save, 'ACT-0039', 0, () => 0);
    expect(started.ok, isTrue);
    save = started.save!;
    expect(slotItemId(save, weaponToolSlotId), isNull);
    expect(slotItemId(save, offhandSlotId), isNull);
    expect(save.currentActivityId, 'ACT-0039');
    expect(save.currentActionId, 'ACN-0109');
  });

  test('the Monk is a level-10 unarmed training fight with no loot', () {
    final enemy = getEnemy(db, 'ENM-0020')!;
    expect(enemy.raw['Display Name'], 'Monk');
    expect(enemy.raw['Combat Level'], 10);
    expect(enemy.raw['Maximum HP'], 350);
    expect(enemy.raw['Min Damage'], 11);
    expect(enemy.raw['Max Damage'], 33);
    expect(enemy.raw['Combat XP'], 1200);
    expect(enemy.raw['Drop Chance'], 0);
    expect(enemy.raw['Reward Table ID'], isNull);

    final action = db.actions.firstWhere((row) => row.raw['Action ID'] == 'ACN-0172');
    expect(action.raw['Display Name'], 'Monk');
    expect(action.raw['XP Reward'], 1200);
    expect(action.raw['Target ID'], 'ENM-0020');
  });

  test('starting monk training unequips weapon and off-hand, then fights unarmed', () {
    var save = _withHands(_atTemple(db), weaponId: 'ITEM-0100', offhandId: 'ITEM-0145');
    expect(slotItemId(save, weaponToolSlotId), 'ITEM-0100');
    expect(slotItemId(save, offhandSlotId), 'ITEM-0145');

    final started = requestActivityStart(db, save, 'ACT-0035', 0, () => 0);
    expect(started.ok, isTrue);
    save = started.save!;
    expect(slotItemId(save, weaponToolSlotId), isNull);
    expect(slotItemId(save, offhandSlotId), isNull);
    expect(save.currentActivityId, 'ACT-0035');
    expect(save.currentActionId, 'ACN-0172');
    expect(save.combatEnemyId, 'ENM-0020');
    expect(save.combatEnemyHp, 350);
    expect(save.inventory.any((stack) => stack.itemId == 'ITEM-0100'), isTrue);
    expect(save.inventory.any((stack) => stack.itemId == 'ITEM-0145'), isTrue);
  });

  test('blessing restores full health without unequipping or starting an activity', () {
    var save = _withHands(_atTemple(db, hp: 250), weaponId: 'ITEM-0100', offhandId: 'ITEM-0145');

    final blessed = requestBlessing(db, save, 0);
    expect(blessed.ok, isTrue);
    expect(blessed.alreadyFull, isFalse);
    expect(blessed.message, 'The monks restore you beyond full health.');
    save = blessed.save!;
    expect(slotItemId(save, weaponToolSlotId), 'ITEM-0100');
    expect(slotItemId(save, offhandSlotId), 'ITEM-0145');
    final maxHp = playerMaxHp(db, save);
    expect(save.currentHp, maxHp + (maxHp * 0.1).floor());
    expect(save.currentActivityId, isNull);
    expect(save.currentActionId, isNull);
  });

  test('blessing reports when health is already full', () {
    final save = createNewSave(db, 0).copyWith(currentLocationId: 'LOC-0036');
    final blessed = requestBlessing(db, save, 0);
    expect(blessed.ok, isTrue);
    expect(blessed.alreadyFull, isFalse);
    expect(blessed.message, 'The monks restore you beyond full health.');
    final maxHp = playerMaxHp(db, blessed.save!);
    expect(blessed.save!.currentHp, maxHp + (maxHp * 0.1).floor());
  });

  test('Temple combat is not a forced-hostile arrival', () {
    final save = createNewSave(db, 0);
    expect(forcedHostileActivity(db, save, 'LOC-0036'), isNull);
    expect(locationIsHostileFor(db, save, 'LOC-0036'), isFalse);
  });

  test('blessing snaps to 110% and keeps surplus when max HP changes', () {
    final save = createNewSave(db, 0).copyWith(currentLocationId: 'LOC-0036', currentHp: 250);
    final first = requestBlessing(db, save, 0);
    expect(first.ok, isTrue);
    final maxHp = playerMaxHp(db, first.save!);
    expect(first.save!.currentHp, maxHp + (maxHp * 0.1).floor());

    final again = requestBlessing(db, first.save!, 0);
    expect(again.alreadyFull, isTrue);
    expect(again.save!.currentHp, first.save!.currentHp);

    expect(currentHpAfterMaxChange(5500, 5000, 4000), 4500);
    expect(currentHpAfterMaxChange(5250, 5000, 4000), 4250);
    expect(currentHpAfterMaxChange(4900, 5000, 4000), 4000);
  });

  test('Old Ent Grove is not a forced-hostile arrival', () {
    final save = createNewSave(db, 0);
    expect(forcedHostileActivity(db, save, 'LOC-0018'), isNull);
    expect(locationIsHostileFor(db, save, 'LOC-0018'), isFalse);
  });
}
