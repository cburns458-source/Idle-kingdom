import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

GameDatabase _db() => filterLaunchContent(assertGameDatabaseShape(contentDatabaseJson()));

PlayerSave _inMeadow(GameDatabase db) {
  return createNewSave(db, 0).copyWith(currentLocationId: 'LOC-0009');
}

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = _db();
  });

  test('stop and start again keeps the rolled meadow action', () {
    var save = _inMeadow(db);
    final first = requestActivityStart(db, save, 'ACT-0012', 0, () => 0);
    expect(first.ok, isTrue);
    save = first.save!;
    expect(save.currentActionId, 'ACN-0105');
    expect(save.heldActionByActivityId['ACT-0012'], 'ACN-0105');

    final stopped = requestActivityStop(db, save, 1);
    expect(stopped.ok, isTrue);
    save = stopped.save!;
    expect(save.currentActivityId, isNull);
    expect(save.heldActionByActivityId['ACT-0012'], 'ACN-0105');

    final again = requestActivityStart(db, save, 'ACT-0012', 2, () => 0.999);
    expect(again.ok, isTrue);
    expect(again.save!.currentActionId, 'ACN-0105');
  });

  test('travel and a different activity leave the held meadow action in place', () {
    var save = _inMeadow(db);
    save = requestActivityStart(db, save, 'ACT-0012', 0, () => 0).save!;
    expect(save.heldActionByActivityId['ACT-0012'], 'ACN-0105');

    save = beginTravelActivityChange(db, save, 1);
    expect(save.currentActivityId, isNull);
    expect(save.heldActionByActivityId['ACT-0012'], 'ACN-0105');

    save = save.copyWith(currentLocationId: 'LOC-0001');
    final farm = requestActivityStart(db, save, 'ACT-0001', 2, () => 0);
    expect(farm.ok, isTrue);
    save = farm.save!;
    expect(save.currentActivityId, 'ACT-0001');
    expect(save.heldActionByActivityId['ACT-0012'], 'ACN-0105');

    save = requestActivityStop(db, save, 3).save!;
    save = save.copyWith(currentLocationId: 'LOC-0009');
    final back = requestActivityStart(db, save, 'ACT-0012', 4, () => 0.999);
    expect(back.save!.currentActionId, 'ACN-0105');
  });

  test('a held action is forgotten when it is no longer in the activity pool', () {
    final save = withHeldAction(_inMeadow(db), 'ACT-0012', 'ACN-0015');
    final started = requestActivityStart(db, save, 'ACT-0012', 0, () => 0);
    expect(started.ok, isTrue);
    expect(started.save!.currentActionId, isNot('ACN-0015'));
    expect(started.save!.currentActionId, 'ACN-0105');
  });

  test('finishing a gathering action forgets it so the next roll can change', () {
    var save = requestActivityStart(db, _inMeadow(db), 'ACT-0012', 0, () => 0).save!;
    final action = db.actions.firstWhere((row) => row.raw['Action ID'] == 'ACN-0105');
    save = completeGatheringAction(db, save, action, () => 0).save;
    expect(save.heldActionByActivityId.containsKey('ACT-0012'), isFalse);

    final next = generateNextAction(db, save, 'ACT-0012', () => 0.999, 10);
    expect(next!.action.raw['Action ID'], isNot('ACN-0105'));
    expect(next.save.heldActionByActivityId['ACT-0012'], next.action.raw['Action ID']);
  });

  test('defeating an enemy forgets the held combat action', () {
    var save = createNewSave(db, 0).copyWith(currentLocationId: 'LOC-0036');
    save = requestActivityStart(db, save, 'ACT-0035', 0, () => 0).save!;
    expect(save.heldActionByActivityId['ACT-0035'], 'ACN-0172');

    final action = db.actions.firstWhere((row) => row.raw['Action ID'] == 'ACN-0172');
    final enemy = getEnemy(db, 'ENM-0020')!;
    final won = applyCombatVictory(db, save, action, enemy, () => 0, 1);
    expect(won.save.heldActionByActivityId.containsKey('ACT-0035'), isFalse);

    save = requestActivityStart(db, save, 'ACT-0035', 0, () => 0).save!;
    final lost = applyCombatDefeat(db, save, 2);
    expect(lost.heldActionByActivityId.containsKey('ACT-0035'), isFalse);
  });
}
