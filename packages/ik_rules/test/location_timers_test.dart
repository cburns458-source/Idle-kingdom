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
    expect(save.discoveredTimerSpotIds, isEmpty);

    save = save.copyWith(
      quests: const [QuestProgress(questId: 'QST-0011', status: 'completed', progress: 1)],
    );
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
      quests: const [QuestProgress(questId: 'QST-0011', status: 'completed', progress: 1)],
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

  test('fishing pots roll 3-6 fish per bait slot and return the pot', () {
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
    expect(timerAtLocationKind(save, 'LOC-0003', 'fishing_pot')?.baitItemIds, isNull);
    final collected = collectLocationTimer(
      db,
      save,
      'LOC-0003',
      'fishing_pot',
      nowMs: DateTime.utc(2026, 3, 1, 18).millisecondsSinceEpoch,
      random: () => 0,
    );
    expect(collected.ok, isTrue);
    expect(collected.loot.map((row) => row.itemId), ['ITEM-0352', fishingPotItemId]);
    expect(collected.loot.firstWhere((row) => row.itemId == 'ITEM-0352').quantity, 9);
    expect(collected.xpGained, 4050);
    expect(collected.bonusXp, [(skillId: 'SKL-0005', xp: 4050)]);
    expect(
      getSkillProgress(collected.save!, 'SKL-0003').xp,
      getSkillProgress(save, 'SKL-0003').xp + 4050,
    );
    expect(
      getSkillProgress(collected.save!, 'SKL-0005').xp,
      getSkillProgress(save, 'SKL-0005').xp + 4050,
    );
  });

  test('baits pots by overall fishing level and awards matching hunter XP', () {
    final camp = createNewSave(db, 0).copyWith(
      currentLocationId: 'LOC-0003',
      skills: const [SkillProgress(skillId: 'SKL-0003', level: 75, xp: 0)],
      inventory: const [
        InventoryStack(itemId: fishingPotItemId, quantity: 1),
        InventoryStack(itemId: 'ITEM-0047', quantity: 3),
        InventoryStack(itemId: 'ITEM-0048', quantity: 3),
        InventoryStack(itemId: 'ITEM-0191', quantity: 3),
      ],
    );
    expect(potBaitOptionsForLocation(db, camp, 'LOC-0003').map((row) => row.itemId), [
      'ITEM-0047',
      'ITEM-0049',
      'ITEM-0051',
    ]);
    expect(
      placeTrap(
        db,
        camp,
        fishingPotItemId,
        nowMs: 0,
        baitItemIds: const ['ITEM-0048', 'ITEM-0048', 'ITEM-0048'],
      ).ok,
      isFalse,
    );
    expect(
      placeTrap(db, camp, fishingPotItemId, nowMs: 0, baitItemIds: const ['ITEM-0047']).ok,
      isFalse,
    );

    final baited = placeTrap(
      db,
      camp,
      fishingPotItemId,
      nowMs: 0,
      baitItemIds: const ['ITEM-0047', 'ITEM-0047', 'ITEM-0047'],
    );
    expect(baited.ok, isTrue);
    expect(baited.save!.inventory.any((stack) => stack.itemId == 'ITEM-0047'), isFalse);
    expect(timerAtLocationKind(baited.save!, 'LOC-0003', 'fishing_pot')?.baitItemIds, [
      'ITEM-0047',
      'ITEM-0047',
      'ITEM-0047',
    ]);
    final haul = collectLocationTimer(
      db,
      baited.save!,
      'LOC-0003',
      'fishing_pot',
      nowMs: trapDurationMs,
      random: () => 0,
    );
    expect(haul.ok, isTrue);
    expect(haul.loot.firstWhere((row) => row.itemId == 'ITEM-0352').quantity, 9);
    expect(haul.xpGained, 4050);
    expect(haul.bonusXp, [(skillId: 'SKL-0005', xp: 4050)]);

    final docks = createNewSave(db, 0).copyWith(
      currentLocationId: 'LOC-0004',
      skills: const [SkillProgress(skillId: 'SKL-0003', level: 75, xp: 0)],
      inventory: const [
        InventoryStack(itemId: fishingPotItemId, quantity: 1),
        InventoryStack(itemId: 'ITEM-0191', quantity: 3),
      ],
    );
    expect(potBaitOptionsForLocation(db, docks, 'LOC-0004').map((row) => row.itemId), [
      'ITEM-0048',
      'ITEM-0050',
      'ITEM-0191',
    ]);
    final lobsterPot = placeTrap(
      db,
      docks,
      fishingPotItemId,
      nowMs: 0,
      baitItemIds: const ['ITEM-0191', 'ITEM-0191', 'ITEM-0191'],
    );
    expect(lobsterPot.ok, isTrue);
    final lobster = collectLocationTimer(
      db,
      lobsterPot.save!,
      'LOC-0004',
      'fishing_pot',
      nowMs: trapDurationMs,
      random: () => 0,
    );
    expect(lobster.ok, isTrue);
    expect(lobster.loot.firstWhere((row) => row.itemId == 'ITEM-0357').quantity, 9);
    expect(lobster.xpGained, 17550);
    expect(lobster.bonusXp, [(skillId: 'SKL-0005', xp: 17550)]);
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

  test('farm patch stays locked until Fennel is heard', () {
    var save = createNewSave(db, 0).copyWith(
      currentLocationId: 'LOC-0001',
      inventory: const [InventoryStack(itemId: 'ITEM-0324', quantity: 2)],
    );
    expect(farmBotanyUnlocked(save), isFalse);
    expect(canPlantBotanySeed(db, save, 'ITEM-0324').ok, isFalse);

    save = save.copyWith(
      quests: const [
        QuestProgress(
          questId: 'QST-0011',
          status: 'active',
          progress: 1,
          counters: <String, num>{'talk:NPC-0014': 1},
        ),
      ],
    );
    expect(farmBotanyUnlocked(save), isTrue);
    expect(canPlantBotanySeed(db, save, 'ITEM-0324', plantQuantity: 2).ok, isTrue);
  });

  test('plants mixed seed types on one patch', () {
    final save = createNewSave(db, 0).copyWith(
      currentLocationId: 'LOC-0031',
      skills: const [SkillProgress(skillId: 'SKL-0014', level: 10, xp: 0)],
      inventory: const [
        InventoryStack(itemId: 'ITEM-0324', quantity: 1),
        InventoryStack(itemId: 'ITEM-0339', quantity: 2),
      ],
    );
    final planted = plantBotanySelection(db, save, const ['ITEM-0324', 'ITEM-0339'], nowMs: 0);
    expect(planted.ok, isTrue);
    final timer = timerAtLocationKind(planted.save!, 'LOC-0031', 'botany');
    expect(timer?.plantedItemIds, ['ITEM-0324', 'ITEM-0339']);
    expect(timer?.outputQuantity, 2);
    expect(timer?.xpReward, 1600);
  });

  test('readyLocationTimerCount only counts finished pots', () {
    final running = LocationTimer(
      locationId: 'LOC-0001',
      kind: 'botany',
      inputItemId: 'ITEM-0324',
      outputQuantity: 1,
      skillId: botanySkillId,
      xpReward: 10,
      startedAt: DateTime.fromMillisecondsSinceEpoch(0).toUtc().toIso8601String(),
      durationMs: 10_000,
    );
    final ready = LocationTimer(
      locationId: 'LOC-0003',
      kind: 'fishing_pot',
      inputItemId: 'ITEM-0103',
      outputQuantity: 1,
      skillId: 'SKL-0007',
      xpReward: 10,
      startedAt: DateTime.fromMillisecondsSinceEpoch(0).toUtc().toIso8601String(),
      durationMs: 1,
    );
    final save = createNewSave(db, 0).copyWith(locationTimers: [running, ready]);
    expect(readyLocationTimerCount(save, 5_000), 1);
    expect(readyLocationTimerCount(save, 10_000), 2);
  });

  test('splits returned seeds by planted pool, not plant order', () {
    const planted = [potatoSeedItemId, carrotSeedItemId, grapeSeedItemId];
    expect(rollReturnedBotanySeed(planted, potatoSeedItemId, () => 0.0), potatoSeedItemId);
    expect(rollReturnedBotanySeed(planted, potatoSeedItemId, () => 0.49), potatoSeedItemId);
    expect(rollReturnedBotanySeed(planted, potatoSeedItemId, () => 0.5), turnipSeedItemId);
    expect(rollReturnedBotanySeed(planted, potatoSeedItemId, () => 0.74), turnipSeedItemId);
    expect(rollReturnedBotanySeed(planted, potatoSeedItemId, () => 0.75), elderBerrySeedItemId);
    expect(rollReturnedBotanySeed(planted, grapeSeedItemId, () => 0.5), elderBerrySeedItemId);
    expect(rollReturnedBotanySeed(planted, carrotSeedItemId, () => 0.5), turnipSeedItemId);

    const twoPotato = [potatoSeedItemId, potatoSeedItemId, carrotSeedItemId];
    expect(rollReturnedBotanySeed(twoPotato, potatoSeedItemId, () => 0.5), turnipSeedItemId);
    expect(rollReturnedBotanySeed(twoPotato, carrotSeedItemId, () => 0.5), turnipSeedItemId);
    expect(
      rollReturnedBotanySeed([potatoSeedItemId], potatoSeedItemId, () => 0.9),
      potatoSeedItemId,
    );
  });

  test('returns mutated seeds on a mixed harvest when the return roll succeeds', () {
    final save = createNewSave(db, 0).copyWith(
      currentLocationId: 'LOC-0031',
      skills: const [SkillProgress(skillId: 'SKL-0014', level: 55, xp: 0)],
      inventory: const [
        InventoryStack(itemId: potatoSeedItemId, quantity: 1),
        InventoryStack(itemId: carrotSeedItemId, quantity: 1),
        InventoryStack(itemId: grapeSeedItemId, quantity: 1),
      ],
    );
    final planted = plantBotanySelection(db, save, const [
      potatoSeedItemId,
      carrotSeedItemId,
      grapeSeedItemId,
    ], nowMs: 0);
    expect(planted.ok, isTrue);
    final rolls = <num>[0, 0, 0, 0, 0, 0, 0, 0.6, 0, 0.6, 0, 0.6];
    var i = 0;
    final collected = collectLocationTimer(
      db,
      planted.save!,
      'LOC-0031',
      'botany',
      nowMs: 10800 * 1000,
      random: () => rolls[i++],
    );
    expect(collected.ok, isTrue);
    expect(collected.loot.where((row) => row.itemId == turnipSeedItemId).first.quantity, 2);
    expect(collected.loot.where((row) => row.itemId == elderBerrySeedItemId).first.quantity, 1);
    expect(collected.loot.any((row) => row.itemId == potatoSeedItemId), isFalse);
  });

  test('lets moonblossom seeds plant at botany 70', () {
    expect(parseBotanySeedSpec(db, moonblossomSeedItemId)?.requiresLevel, 70);
    expect(parseBotanySeedSpec(db, turnipSeedItemId)?.xp, 6000);
    expect(parseBotanySeedSpec(db, turnipSeedItemId)?.requiresLevel, 27);
  });

  test('computes live-plant chance from level, requirement, and compost', () {
    expect(botanySuccessChancePercent(1, 1), 25.5);
    expect(botanySuccessChancePercent(10, 1), 34.5);
    expect(botanySuccessChancePercent(10, 10), 30);
    expect(botanySuccessChancePercent(10, 10, usedCompost: true), 55);
    expect(botanySuccessChancePercent(200, 1, usedCompost: true), 100);
  });

  test('offers compost collect at every botany patch except The Shallows', () {
    expect(locationHasCompostCollect('LOC-0001'), isTrue);
    expect(locationHasCompostCollect('LOC-0046'), isTrue);
    expect(locationHasCompostCollect('LOC-0043'), isFalse);
    expect(locationHasCompostCollect('LOC-0036'), isFalse);
    expect(locationHasCompostCollect('LOC-0002'), isFalse);
    expect(compostCollectActivityAt(db, 'LOC-0001')?.activityId, 'ACT-0062');
    expect(compostCollectActivityAt(db, 'LOC-0046')?.activityId, 'ACT-0065');
    expect(compostCollectActivityAt(db, 'LOC-0043'), isNull);
    expect(compostCollectActivityAt(db, 'LOC-0036'), isNull);
    expect(db.items.any((item) => item.itemId == compostItemId), isTrue);
  });

  test('spends compost when planting and only awards lived plants', () {
    final save = createNewSave(db, 0).copyWith(
      currentLocationId: 'LOC-0031',
      skills: const [SkillProgress(skillId: 'SKL-0014', level: 1, xp: 0)],
      inventory: const [
        InventoryStack(itemId: potatoSeedItemId, quantity: 2),
        InventoryStack(itemId: compostItemId, quantity: 3),
      ],
      quests: const [QuestProgress(questId: 'QST-0011', status: 'completed', progress: 1)],
    );
    final planted = plantBotanySelection(
      db,
      save,
      const [potatoSeedItemId],
      nowMs: 0,
      usedCompost: true,
    );
    expect(planted.ok, isTrue);
    expect(
      planted.save!.inventory.where((stack) => stack.itemId == compostItemId).first.quantity,
      2,
    );
    expect(timerAtLocationKind(planted.save!, 'LOC-0031', 'botany')?.usedCompost, isTrue);

    final short = plantBotanySelection(
      db,
      save.copyWith(inventory: const [InventoryStack(itemId: potatoSeedItemId, quantity: 1)]),
      const [potatoSeedItemId],
      nowMs: 0,
      usedCompost: true,
    );
    expect(short.ok, isFalse);
    expect(short.reason, 'You need 1 compost for this planting.');

    final kelp = plantBotanySelection(
      db,
      save.copyWith(
        currentLocationId: 'LOC-0043',
        skills: const [SkillProgress(skillId: 'SKL-0014', level: 40, xp: 0)],
        inventory: const [
          InventoryStack(itemId: 'ITEM-0350', quantity: 1),
          InventoryStack(itemId: compostItemId, quantity: 5),
        ],
      ),
      const ['ITEM-0350'],
      nowMs: 0,
      usedCompost: true,
    );
    expect(kelp.ok, isFalse);
    expect(kelp.reason, 'Compost cannot be used on kelp.');

    final dying = plantBotanySelection(db, save, const [
      potatoSeedItemId,
      potatoSeedItemId,
    ], nowMs: 0);
    expect(dying.ok, isTrue);
    var i = 0;
    final collected = collectLocationTimer(
      db,
      dying.save!,
      'LOC-0031',
      'botany',
      nowMs: 10800 * 1000,
      random: () => <num>[0.99, 0.99][i++],
    );
    expect(collected.ok, isTrue);
    expect(collected.loot, isEmpty);
    expect(collected.xpGained, 0);
  });

  test('mutates only from seeds that lived', () {
    final save = createNewSave(db, 0).copyWith(
      currentLocationId: 'LOC-0031',
      skills: const [SkillProgress(skillId: 'SKL-0014', level: 55, xp: 0)],
      inventory: const [
        InventoryStack(itemId: potatoSeedItemId, quantity: 1),
        InventoryStack(itemId: carrotSeedItemId, quantity: 1),
      ],
    );
    final planted = plantBotanySelection(db, save, const [
      potatoSeedItemId,
      carrotSeedItemId,
    ], nowMs: 0);
    expect(planted.ok, isTrue);
    var i = 0;
    final rolls = <num>[0, 0, 0.99, 0];
    final collected = collectLocationTimer(
      db,
      planted.save!,
      'LOC-0031',
      'botany',
      nowMs: 10800 * 1000,
      random: () => rolls[i++],
    );
    expect(collected.ok, isTrue);
    expect(collected.loot.any((row) => row.itemId == turnipSeedItemId), isFalse);
    expect(collected.loot.any((row) => row.itemId == potatoSeedItemId), isTrue);
    expect(collected.xpGained, 1000);
  });
}
