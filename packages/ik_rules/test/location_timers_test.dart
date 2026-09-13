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

  test('fishing pots roll 1-3 of each unlocked fish and return the pot', () {
    var save = createNewSave(db, 0).copyWith(
      currentLocationId: 'LOC-0003',
      skills: const [SkillProgress(skillId: 'SKL-0003', level: 50, xp: 848633)],
      inventory: const [InventoryStack(itemId: fishingPotItemId, quantity: 1)],
    );
    final placed = placeTrap(
      db,
      save,
      fishingPotItemId,
      nowMs: DateTime.utc(2026, 3, 1, 12).millisecondsSinceEpoch,
    );
    expect(placed.ok, isTrue);
    save = placed.save!;
    final collected = collectLocationTimer(
      db,
      save,
      'LOC-0003',
      'fishing_pot',
      nowMs: DateTime.utc(2026, 3, 1, 18).millisecondsSinceEpoch,
      random: () => 0,
    );
    expect(collected.ok, isTrue);
    expect(
      collected.loot.map((row) => row.itemId),
      containsAll(<String>['ITEM-0352', 'ITEM-0354', fishingPotItemId]),
    );
    expect(collected.loot.any((row) => row.itemId == 'ITEM-0356'), isFalse);
    for (final fishId in <String>['ITEM-0352', 'ITEM-0354']) {
      final qty = collected.loot.firstWhere((row) => row.itemId == fishId).quantity;
      expect(qty, inInclusiveRange(1, 3));
    }
  });

  test('full inventory leaves a ready timer uncollected', () {
    final save = createNewSave(db, 0).copyWith(
      currentLocationId: 'LOC-0001',
      inventory: [
        for (var index = 0; index < inventorySlotLimit; index++)
          InventoryStack(itemId: 'FILL-$index', quantity: 1),
      ],
      locationTimers: [
        LocationTimer(
          locationId: 'LOC-0001',
          kind: 'botany',
          inputItemId: 'ITEM-0324',
          outputItemId: 'ITEM-0025',
          outputQuantity: 1,
          skillId: botanySkillId,
          xpReward: 10,
          startedAt: '2026-01-01T00:00:00.000Z',
          durationMs: 1,
        ),
      ],
    );
    final collected = collectLocationTimer(
      db,
      save,
      'LOC-0001',
      'botany',
      nowMs: DateTime.utc(2026, 1, 1, 1).millisecondsSinceEpoch,
      random: () => 0,
    );
    expect(collected.ok, isFalse);
    expect(collected.reason, timerInventoryFullHarvestReason);
    expect(timerAtLocationKind(save, 'LOC-0001', 'botany'), isNotNull);
  });

  test('full inventory asks for room to collect a pot catch', () {
    final save = createNewSave(db, 0).copyWith(
      currentLocationId: 'LOC-0003',
      skills: const [SkillProgress(skillId: 'SKL-0003', level: 14, xp: 2000)],
      inventory: [
        for (var index = 0; index < inventorySlotLimit; index++)
          InventoryStack(itemId: 'FILL-$index', quantity: 1),
      ],
      locationTimers: [
        LocationTimer(
          locationId: 'LOC-0003',
          kind: 'fishing_pot',
          inputItemId: fishingPotItemId,
          outputItemId: null,
          outputQuantity: 1,
          skillId: 'SKL-0003',
          xpReward: 150,
          startedAt: '2026-01-01T00:00:00.000Z',
          durationMs: 1,
        ),
      ],
    );
    final collected = collectLocationTimer(
      db,
      save,
      'LOC-0003',
      'fishing_pot',
      nowMs: DateTime.utc(2026, 1, 1, 8).millisecondsSinceEpoch,
      random: () => 0,
    );
    expect(collected.ok, isFalse);
    expect(collected.reason, timerInventoryFullCatchReason);
    expect(timerAtLocationKind(save, 'LOC-0003', 'fishing_pot'), isNotNull);
  });
}
