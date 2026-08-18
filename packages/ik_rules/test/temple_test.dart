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
    expect(activities.map((row) => row.raw['Contextual Name']), ['Train with the monks']);
    expect(db.activities.any((row) => row.activityId == 'ACT-0036'), isFalse);
  });

  test('the Monk is a level-10 unarmed training fight with no loot', () {
    final enemy = getEnemy(db, 'ENM-0020')!;
    expect(enemy.raw['Display Name'], 'Monk');
    expect(enemy.raw['Combat Level'], 10);
    expect(enemy.raw['Maximum HP'], 500);
    expect(enemy.raw['Min Damage'], 11);
    expect(enemy.raw['Max Damage'], 33);
    expect(enemy.raw['Combat XP'], 5000);
    expect(enemy.raw['Drop Chance'], 0);
    expect(enemy.raw['Reward Table ID'], isNull);

    final action = db.actions.firstWhere((row) => row.raw['Action ID'] == 'ACN-0172');
    expect(action.raw['Display Name'], 'Monk');
    expect(action.raw['XP Reward'], 5000);
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
    expect(save.combatEnemyHp, 500);
    expect(save.inventory.any((stack) => stack.itemId == 'ITEM-0100'), isTrue);
    expect(save.inventory.any((stack) => stack.itemId == 'ITEM-0145'), isTrue);
  });

  test('blessing restores full health without unequipping or starting an activity', () {
    var save = _withHands(_atTemple(db, hp: 250), weaponId: 'ITEM-0100', offhandId: 'ITEM-0145');

    final blessed = requestBlessing(db, save, 0);
    expect(blessed.ok, isTrue);
    expect(blessed.alreadyFull, isFalse);
    expect(blessed.message, 'The monks restore you to full health.');
    save = blessed.save!;
    expect(slotItemId(save, weaponToolSlotId), 'ITEM-0100');
    expect(slotItemId(save, offhandSlotId), 'ITEM-0145');
    expect(save.currentHp, playerMaxHp(db, save));
    expect(save.currentActivityId, isNull);
    expect(save.currentActionId, isNull);
  });

  test('blessing reports when health is already full', () {
    final save = createNewSave(db, 0).copyWith(currentLocationId: 'LOC-0036');
    final blessed = requestBlessing(db, save, 0);
    expect(blessed.ok, isTrue);
    expect(blessed.alreadyFull, isTrue);
    expect(blessed.message, 'You are already at full health.');
    expect(blessed.save!.currentHp, playerMaxHp(db, blessed.save!));
  });

  test('Temple combat is not a forced-hostile arrival', () {
    final save = createNewSave(db, 0);
    expect(forcedHostileActivity(db, save, 'LOC-0036'), isNull);
    expect(locationIsHostileFor(db, save, 'LOC-0036'), isFalse);
  });
}
