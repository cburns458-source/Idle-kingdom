import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = assertGameDatabaseShape(contentDatabaseJson());
  });

  test('timerSpotKey and parseTimerSpotKey round-trip', () {
    expect(timerSpotKey('botany', 'LOC-0001'), 'botany:LOC-0001');
    expect(timerSpotKey('fishing_pot', 'LOC-0003'), 'fishing_pot:LOC-0003');
    expect(parseTimerSpotKey('botany:LOC-0001'), (kind: 'botany', locationId: 'LOC-0001'));
    expect(parseTimerSpotKey('fishing_pot:LOC-0003'), (
      kind: 'fishing_pot',
      locationId: 'LOC-0003',
    ));
    expect(parseTimerSpotKey('hunting_trap:LOC-0009'), isNull);
    expect(parseTimerSpotKey(''), isNull);
    expect(parseTimerSpotKey('botany'), isNull);
    expect(parseTimerSpotKey('botany:'), isNull);
    expect(parseTimerSpotKey(':LOC-0001'), isNull);
    expect(parseTimerSpotKey('unknown:LOC-0001'), isNull);
  });

  test('discoverTimerSpotsForLocation adds matching keys once', () {
    var save = createNewSave(db, 0);
    expect(save.discoveredTimerSpotIds, isEmpty);

    save = discoverTimerSpotsForLocation(save, 'LOC-0001');
    expect(save.discoveredTimerSpotIds, ['botany:LOC-0001']);
    expect(identical(discoverTimerSpotsForLocation(save, 'LOC-0001'), save), isTrue);

    save = discoverTimerSpotsForLocation(save, 'LOC-0009');
    expect(save.discoveredTimerSpotIds, contains('botany:LOC-0009'));
    expect(save.discoveredTimerSpotIds, isNot(contains('hunting_trap:LOC-0009')));

    save = discoverTimerSpotsForLocation(save, 'LOC-0003');
    expect(save.discoveredTimerSpotIds, contains('fishing_pot:LOC-0003'));

    expect(identical(discoverTimerSpotsForLocation(save, 'LOC-9999'), save), isTrue);
  });

  test('plant and place discover their spots', () {
    var save = createNewSave(db, 0).copyWith(
      currentLocationId: 'LOC-0001',
      inventory: const [InventoryStack(itemId: 'ITEM-0324', quantity: 3)],
    );
    final planted = plantBotanySeed(db, save, 'ITEM-0324', nowMs: 0, plantQuantity: 3);
    expect(planted.ok, isTrue);
    expect(planted.save!.discoveredTimerSpotIds, contains('botany:LOC-0001'));

    save = createNewSave(db, 0).copyWith(
      currentLocationId: 'LOC-0003',
      skills: const [SkillProgress(skillId: 'SKL-0003', level: 14, xp: 2000)],
      inventory: const [InventoryStack(itemId: fishingPotItemId, quantity: 1)],
    );
    final placed = placeTrap(db, save, fishingPotItemId, nowMs: 0);
    expect(placed.ok, isTrue);
    expect(placed.save!.discoveredTimerSpotIds, contains('fishing_pot:LOC-0003'));
  });
}
