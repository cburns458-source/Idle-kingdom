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
    expect(timerSpotKey('hunting_trap', 'LOC-0008'), 'hunting_trap:LOC-0008');
    expect(timerSpotKey('fishing_trap', 'LOC-0003'), 'fishing_trap:LOC-0003');
    expect(parseTimerSpotKey('botany:LOC-0001'), (kind: 'botany', locationId: 'LOC-0001'));
    expect(parseTimerSpotKey('hunting_trap:LOC-0009'), (
      kind: 'hunting_trap',
      locationId: 'LOC-0009',
    ));
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
    expect(save.discoveredTimerSpotIds, containsAll(['botany:LOC-0009', 'hunting_trap:LOC-0009']));

    save = discoverTimerSpotsForLocation(save, 'LOC-0003');
    expect(save.discoveredTimerSpotIds, contains('fishing_trap:LOC-0003'));

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
      currentLocationId: 'LOC-0008',
      inventory: const [InventoryStack(itemId: huntingTrapItemId, quantity: 1)],
    );
    final placed = placeTrap(db, save, huntingTrapItemId, nowMs: 0);
    expect(placed.ok, isTrue);
    expect(placed.save!.discoveredTimerSpotIds, contains('hunting_trap:LOC-0008'));
  });

  test('Meadow can hold botany and hunting trap; collecting one leaves the other', () {
    var save = createNewSave(db, 0).copyWith(
      currentLocationId: 'LOC-0009',
      inventory: const [
        InventoryStack(itemId: 'ITEM-0324', quantity: 3),
        InventoryStack(itemId: huntingTrapItemId, quantity: 1),
      ],
    );
    expect(canPlantBotanySeed(db, save, 'ITEM-0324').ok, isTrue);
    expect(canPlaceTrap(db, save, huntingTrapItemId).ok, isTrue);

    final planted = plantBotanySeed(db, save, 'ITEM-0324', nowMs: 0, plantQuantity: 3);
    expect(planted.ok, isTrue);
    expect(timerAtLocationKind(planted.save!, 'LOC-0009', 'botany')?.kind, 'botany');
    expect(canPlaceTrap(db, planted.save!, huntingTrapItemId).ok, isTrue);

    final placed = placeTrap(db, planted.save!, huntingTrapItemId, nowMs: 0);
    expect(placed.ok, isTrue);
    expect(timerAtLocationKind(placed.save!, 'LOC-0009', 'botany')?.kind, 'botany');
    expect(timerAtLocationKind(placed.save!, 'LOC-0009', 'hunting_trap')?.kind, 'hunting_trap');
    expect(canPlantBotanySeed(db, placed.save!, 'ITEM-0324').ok, isFalse);
    expect(
      canPlaceTrap(db, placed.save!, huntingTrapItemId).reason,
      'A hunting trap is already set here.',
    );

    final collectedBotany = collectLocationTimer(
      db,
      placed.save!,
      'LOC-0009',
      'botany',
      nowMs: 3 * 60 * 60 * 1000,
      random: () => 0,
    );
    expect(collectedBotany.ok, isTrue);
    expect(timerAtLocationKind(collectedBotany.save!, 'LOC-0009', 'botany'), isNull);
    expect(
      timerAtLocationKind(collectedBotany.save!, 'LOC-0009', 'hunting_trap')?.kind,
      'hunting_trap',
    );

    final collectedTrap = collectLocationTimer(
      db,
      collectedBotany.save!,
      'LOC-0009',
      'hunting_trap',
      nowMs: 6 * 60 * 60 * 1000,
      random: () => 0,
    );
    expect(collectedTrap.ok, isTrue);
    expect(timerAtLocation(collectedTrap.save!, 'LOC-0009'), isNull);
  });
}
