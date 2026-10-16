import 'dart:io';

import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

const _expectedContentVersion = '2026-10-16-plain-descriptions';
const _nowMs = 1760486400000; // 2026-10-15T00:00:00.000Z
const _apothecary = 'LOC-0026';
const _kitchens = <String>['LOC-0023', 'LOC-0015', 'LOC-0030', 'LOC-0053', 'LOC-0049'];
const _crossbreedingSeeds = <String>[
  'ITEM-0331',
  'ITEM-0332',
  'ITEM-0335',
  'ITEM-0338',
  'ITEM-0349',
];

const _sixDosePotions = <({String itemId, String key})>[
  (itemId: 'ITEM-0070', key: 'luck_potion'),
  (itemId: 'ITEM-0071', key: 'speed_potion'),
  (itemId: 'ITEM-0072', key: 'strength_potion'),
  (itemId: 'ITEM-0073', key: 'poison_potion'),
  (itemId: 'ITEM-0210', key: 'minor_luck_potion'),
  (itemId: 'ITEM-0211', key: 'minor_strength_potion'),
  (itemId: 'ITEM-0212', key: 'greater_strength_potion'),
  (itemId: 'ITEM-0213', key: 'masterwork_draught'),
  (itemId: 'ITEM-0439', key: 'fernleaf_tonic'),
  (itemId: 'ITEM-0440', key: 'mosstole_brew'),
  (itemId: 'ITEM-0441', key: 'augur_draught'),
  (itemId: 'ITEM-0442', key: 'moonblossom_elixir'),
];

const _herbPotions = <({String itemId, String recipeId, String herbId})>[
  (itemId: 'ITEM-0439', recipeId: 'RCP-0078', herbId: 'ITEM-0031'),
  (itemId: 'ITEM-0440', recipeId: 'RCP-0079', herbId: 'ITEM-0032'),
  (itemId: 'ITEM-0441', recipeId: 'RCP-0080', herbId: 'ITEM-0033'),
  (itemId: 'ITEM-0442', recipeId: 'RCP-0081', herbId: 'ITEM-0207'),
];

GameDatabase _launch() => filterLaunchContent(assertGameDatabaseShape(contentDatabaseJson()));

GameDatabase _source() => assertGameDatabaseShape(contentDatabaseJson());

String _versionFromSource(String source, RegExp pattern) {
  final match = pattern.firstMatch(source);
  expect(match, isNotNull, reason: source);
  return match!.group(1)!;
}

RandomFn seqRandom(List<num> values) {
  var i = 0;
  return () {
    final value = values[i < values.length ? i : values.length - 1];
    i += 1;
    return value.toDouble();
  };
}

num weightedShare(List<RewardEntryRow> entries, String itemId) {
  final usable = [
    for (final entry in entries)
      if (entry.raw['Status'] != 'Needs Data' &&
          entry.raw['Weight'] is num &&
          (entry.raw['Weight'] as num) > 0)
        entry,
  ];
  final total = usable.fold<num>(0, (sum, entry) => sum + (entry.raw['Weight'] as num));
  final weight = usable
      .where((entry) => entry.raw['Reward ID / Value'] == itemId)
      .fold<num>(0, (sum, entry) => sum + (entry.raw['Weight'] as num));
  expect(total, greaterThan(0));
  return weight / total;
}

void main() {
  late GameDatabase db;
  late GameDatabase source;
  late CodexIndex launchCodex;
  late CodexIndex sourceCodex;

  setUpAll(() {
    db = _launch();
    source = _source();
    launchCodex = CodexIndex(db);
    sourceCodex = CodexIndex(source);
  });

  ItemRow item(String id) => db.items.firstWhere((row) => row.itemId == id);

  ItemRow sourceItem(String id) => source.items.firstWhere((row) => row.itemId == id);

  RecipeRow recipe(String id) => db.recipes.firstWhere((row) => row.raw['Recipe ID'] == id);

  EquipmentRow equipment(String itemId) {
    return db.equipment.firstWhere((row) => row.raw['Item ID'] == itemId);
  }

  PlayerSave withPotion(PlayerSave save, String itemId, [num quantity = 1]) {
    return equipStackToSlot(save, potionSlotId, itemId, quantity);
  }

  test('content version is 2026-10-16-plain-descriptions in both loaders', () {
    final root = parityRepoRoot();
    final tsSource = File('${root.path}/src/game/data/loadDatabase.ts').readAsStringSync();
    final dartSource = File('${root.path}/packages/ik_content/lib/src/load_database.dart')
        .readAsStringSync();
    final tsVersion = _versionFromSource(
      tsSource,
      RegExp(r"export const DATABASE_CONTENT_VERSION = '([^']+)'"),
    );
    final dartVersion = _versionFromSource(
      dartSource,
      RegExp(r"const String databaseContentVersion = '([^']+)';"),
    );
    expect(databaseContentVersion, _expectedContentVersion);
    expect(tsVersion, _expectedContentVersion);
    expect(dartVersion, _expectedContentVersion);
  });

  test('the four new potions parse to their tagged effects and last 6 uses', () {
    final tonic = parsePotionEffect(equipment('ITEM-0439'), 'ITEM-0439');
    expect(tonic?.instantHealMaxHpPercent, 5);
    expect(tonic?.actionsRemaining, potionActionDuration);
    expect(tonic?.actionsRemaining, 6);
    expect(tonic?.scope, 'one_combat_encounter');

    final brew = parsePotionEffect(equipment('ITEM-0440'), 'ITEM-0440');
    expect(brew?.regenMaxHpPercentPerRound, 3);
    expect(brew?.actionsRemaining, 6);

    final draught = parsePotionEffect(equipment('ITEM-0441'), 'ITEM-0441');
    expect(draught?.damageBonusMin, 10);
    expect(draught?.damageBonusMax, 30);
    expect(draught?.actionsRemaining, 6);

    final elixir = parsePotionEffect(equipment('ITEM-0442'), 'ITEM-0442');
    expect(elixir?.damageBonusMin, 30);
    expect(elixir?.damageBonusMax, 90);
    expect(elixir?.actionsRemaining, 6);
  });

  test('Fernleaf tonic heals 5% of max HP instantly, capped at max HP', () {
    final effect = parsePotionEffect(equipment('ITEM-0439'), 'ITEM-0439');
    expect(applyPotionInstantHeal(400, 1000, effect), 450);
    expect(applyPotionInstantHeal(980, 1000, effect), 1000);
    expect(applyPotionInstantHeal(1000, 1000, effect), 1000);

    final enemy = db.enemies.firstWhere((row) => row.raw['Enemy ID'] == 'ENM-0001');
    final action = db.actions.firstWhere((row) => row.raw['Action ID'] == 'ACN-0001');
    final hurt = withPotion(createNewSave(db, 0), 'ITEM-0439').copyWith(currentHp: 400);
    final started = beginCombatSave(db, hurt, action, enemy, '2026-01-01T00:00:00.000Z');
    expect(started.currentHp, 400 + (started.maxHp * 0.05).floor());
    expect(started.currentHp, lessThanOrEqualTo(started.maxHp));
    expect(started.activePotionEffect?.actionsRemaining, 6);
  });

  test('Mosstole brew heals 3% of max HP each combat round, capped at max HP', () {
    final effect = parsePotionEffect(equipment('ITEM-0440'), 'ITEM-0440');
    expect(applyPotionRegenHeal(400, 1000, effect), 430);
    expect(applyPotionRegenHeal(990, 1000, effect), 1000);
    expect(applyPotionRegenHeal(1000, 1000, effect), 1000);

    final enemy = db.enemies.firstWhere((row) => row.raw['Enemy ID'] == 'ENM-0001');
    final action = db.actions.firstWhere((row) => row.raw['Action ID'] == 'ACN-0001');
    final started = beginCombatSave(
      db,
      withPotion(createNewSave(db, 0), 'ITEM-0440').copyWith(currentHp: 400),
      action,
      enemy,
      '2026-01-01T00:00:00.000Z',
    );
    final before = started.currentHp;
    final round = resolveCombatRound(db, started, enemy, started.combatEnemyHp ?? 0, () => 0);
    expect(
      round.playerHpAfterPlayer,
      applyPotionRegenHeal(before, started.maxHp, started.activePotionEffect),
    );
    expect(round.playerHpAfterPlayer, lessThanOrEqualTo(started.maxHp));
    expect(started.activePotionEffect?.actionsRemaining, 6);
  });

  test('Augur draught adds +10 min / +30 max flat damage', () {
    final save = withPotion(createNewSave(db, 0), 'ITEM-0441');
    final enemy = db.enemies.firstWhere((row) => row.raw['Enemy ID'] == 'ENM-0001');
    final action = db.actions.firstWhere((row) => row.raw['Action ID'] == 'ACN-0001');
    final started = beginCombatSave(db, save, action, enemy, '2026-01-01T00:00:00.000Z');
    expect(started.activePotionEffect?.damageBonusMin, 10);
    expect(started.activePotionEffect?.damageBonusMax, 30);
    expect(potionFlatDamageBonus(started.activePotionEffect).min, 10);
    expect(potionFlatDamageBonus(started.activePotionEffect).max, 30);
    expect(started.activePotionEffect?.actionsRemaining, 6);
  });

  test('Moonblossom elixir adds +30 min / +90 max flat damage', () {
    final save = withPotion(createNewSave(db, 0), 'ITEM-0442');
    final enemy = db.enemies.firstWhere((row) => row.raw['Enemy ID'] == 'ENM-0001');
    final action = db.actions.firstWhere((row) => row.raw['Action ID'] == 'ACN-0001');
    final started = beginCombatSave(db, save, action, enemy, '2026-01-01T00:00:00.000Z');
    expect(started.activePotionEffect?.damageBonusMin, 30);
    expect(started.activePotionEffect?.damageBonusMax, 90);
    expect(potionFlatDamageBonus(started.activePotionEffect).min, 30);
    expect(potionFlatDamageBonus(started.activePotionEffect).max, 90);
    expect(started.activePotionEffect?.actionsRemaining, 6);
  });

  test('every 6-dose potion display name ends in (6) and keeps its id and key', () {
    for (final potion in _sixDosePotions) {
      final row = item(potion.itemId);
      expect(row.itemId, potion.itemId, reason: potion.itemId);
      expect(row.internalKey, potion.key, reason: potion.itemId);
      expect(row.displayName.endsWith('(6)'), isTrue, reason: potion.itemId);
    }
  });

  test('the four new recipes use exactly 1 herb + Water x1', () {
    for (final potion in _herbPotions) {
      final ingredients = recipeIngredients(recipe(potion.recipeId));
      expect(ingredients, hasLength(2), reason: potion.recipeId);
      expect(
        ingredients.any((entry) => entry.itemId == potion.herbId && entry.quantity == 1),
        isTrue,
        reason: potion.recipeId,
      );
      expect(
        ingredients.any((entry) => entry.itemId == waterItemId && entry.quantity == 1),
        isTrue,
        reason: potion.recipeId,
      );
    }
  });

  test('water is free and unconsumed at every Alchemy station and kitchen', () {
    final base = createNewSave(db, 0);
    final stations = alchemyStationLocationIds(db);
    expect(stations, {'LOC-0026', 'LOC-0030'});
    for (final loc in stations) {
      final save = base.copyWith(currentLocationId: loc);
      expect(isAmbientIngredientAt(db, save, waterItemId), isTrue, reason: loc);
      expect(ingredientOwned(db, save, waterItemId), double.infinity, reason: loc);
    }
    for (final loc in _kitchens) {
      final save = base.copyWith(currentLocationId: loc);
      expect(ingredientOwned(db, save, waterItemId), double.infinity, reason: loc);
    }
    expect(ingredientOwned(db, base.copyWith(currentLocationId: 'LOC-0001'), waterItemId), 0);
  });

  test('Kitchen scraps are free in kitchens, including Manor and Giant Camp, but not at the apothecary', () {
    final base = createNewSave(db, 0);
    for (final loc in _kitchens) {
      final save = base.copyWith(currentLocationId: loc);
      expect(ingredientOwned(db, save, kitchenScrapsItemId), double.infinity, reason: loc);
    }
    final apothecary = base.copyWith(currentLocationId: _apothecary);
    expect(isAtAlchemyStation(db, apothecary), isTrue);
    expect(ingredientOwned(db, apothecary, kitchenScrapsItemId), 0);
    expect(isAmbientIngredientAt(db, apothecary, kitchenScrapsItemId), isFalse);
  });

  test('cancelling a queued brew refunds everything except water', () {
    final tonic = recipe('RCP-0078');
    var save = createNewSave(db, 0).copyWith(currentLocationId: _apothecary);
    save = addItemToInventory(save, 'ITEM-0031', 5);
    save = addItemToInventory(save, waterItemId, 2);
    expect(maxCraftsFromMaterials(db, save, tonic), 5);

    final queued = beginProductionQueue(db, save, 'ACT-0020', 'RCP-0078', 3, 0);
    expect(queued.ok, isTrue);
    expect(queued.save!.inventory.firstWhere((stack) => stack.itemId == 'ITEM-0031').quantity, 2);
    expect(queued.save!.inventory.firstWhere((stack) => stack.itemId == waterItemId).quantity, 2);

    final cancelled = cancelProductionActivity(db, queued.save!);
    expect(cancelled.inventory.firstWhere((stack) => stack.itemId == 'ITEM-0031').quantity, 5);
    expect(cancelled.inventory.firstWhere((stack) => stack.itemId == waterItemId).quantity, 2);
  });

  test('Apothecary buys the four new potions but does not sell them', () {
    final shop = getShop(db, 'SHP-0010')!;
    const potions = <({String itemId, int price})>[
      (itemId: 'ITEM-0439', price: 4),
      (itemId: 'ITEM-0440', price: 8),
      (itemId: 'ITEM-0441', price: 40),
      (itemId: 'ITEM-0442', price: 240),
    ];
    final stock = shopStockEntries(shop).map((entry) => entry.itemId).toList();
    var save = createNewSave(db, _nowMs).copyWith(currentLocationId: shop.locationId, gold: 0);
    for (var i = 0; i < potions.length; i += 1) {
      final potion = potions[i];
      expect(shop.raw['Entry ${i + 7} Mode'], 'Buy', reason: potion.itemId);
      expect(shop.raw['Entry ${i + 7} Item ID'], potion.itemId);
      expect(stock.contains(potion.itemId), isFalse, reason: potion.itemId);
      expect(shopSellsItem(shop, potion.itemId), isFalse, reason: potion.itemId);
      expect(playerSellPrice(db, shop, potion.itemId), potion.price);

      expect(
        confirmShopOffer(
          db,
          save.copyWith(gold: 10000),
          'SHP-0010',
          ShopOffer(buys: <ShopOfferLine>[ShopOfferLine(itemId: potion.itemId, quantity: 1)]),
          nowMs: _nowMs,
        ).ok,
        isFalse,
        reason: potion.itemId,
      );

      save = addItemToInventory(save, potion.itemId, 1);
      final sold = confirmShopOffer(
        db,
        save,
        'SHP-0010',
        ShopOffer(sells: <ShopOfferLine>[ShopOfferLine(itemId: potion.itemId, quantity: 1)]),
        nowMs: _nowMs,
      );
      expect(sold.ok, isTrue, reason: potion.itemId);
      save = sold.save!;
    }
    expect(save.gold, 4 + 8 + 40 + 240);
  });

  test('Strength sells for ~260 above Minor Strength; Minor Luck ~120 below Luck', () {
    expect(item('ITEM-0072').baseSellValue, 260);
    expect(item('ITEM-0211').baseSellValue, 210);
    expect(item('ITEM-0072').baseSellValue, greaterThan(item('ITEM-0211').baseSellValue!));
    expect(item('ITEM-0210').baseSellValue, 120);
    expect(item('ITEM-0070').baseSellValue, 294);
    expect(item('ITEM-0210').baseSellValue, lessThan(item('ITEM-0070').baseSellValue!));
  });

  test('pheasant feathers drop about 15% per hunt', () {
    final action = db.actions.firstWhere((row) => row.raw['Action ID'] == 'ACN-0017');
    expect(action.raw['Drop Chance'], 60);
    expect(action.raw['Reward Table ID'], 'RWT-0052');
    final entries = db.rewardEntries
        .where((row) => row.raw['Reward Table ID'] == 'RWT-0052')
        .toList();
    expect(weightedShare(entries, 'ITEM-0039') * 60, closeTo(15, 0.01));
  });

  test('Troll tooth drops about 11.2% on the Rock Troll table', () {
    final action = db.actions.firstWhere((row) => row.raw['Action ID'] == 'ACN-0005');
    final enemy = db.enemies.firstWhere((row) => row.raw['Enemy ID'] == 'ENM-0007');
    expect(action.raw['Reward Table ID'], 'RWT-0198');
    expect(enemy.raw['Reward Table ID'], 'RWT-0198');
    expect(action.raw['Drop Chance'], 32);
    expect(enemy.raw['Drop Chance'], 32);
    final mother = db.enemies.firstWhere((row) => row.raw['Enemy ID'] == 'ENM-0023');
    expect(mother.raw['Reward Table ID'], 'RWT-0012');
    final entries = db.rewardEntries
        .where((row) => row.raw['Reward Table ID'] == 'RWT-0198')
        .toList();
    expect(weightedShare(entries, 'ITEM-0201') * 32, closeTo(11.2, 0.01));
  });

  test('Goblin Scouts drop Wooden dagger, not Bronze dagger', () {
    final entries = db.rewardEntries
        .where((row) => row.raw['Reward Table ID'] == 'RWT-0003')
        .toList();
    final rwe0006 = entries.firstWhere((row) => row.raw['Reward Entry ID'] == 'RWE-0006');
    expect(rwe0006.raw['Reward ID / Value'], 'ITEM-0125');
    expect(item('ITEM-0125').displayName, 'Wooden dagger');
    expect(entries.any((row) => row.raw['Reward ID / Value'] == 'ITEM-0225'), isFalse);
    final warrior = db.rewardEntries.where((row) => row.raw['Reward Table ID'] == 'RWT-0004');
    expect(warrior.any((row) => row.raw['Reward ID / Value'] == 'ITEM-0225'), isTrue);
  });

  test('every drop bonus applies when rolling combat loot', () {
    final action = db.actions.firstWhere((row) => row.raw['Action ID'] == 'ACN-0003');
    expect(action.raw['Drop Chance'], 25);
    final base = createNewSave(db, 0);
    final boosted = base.copyWith(
      activePotionEffect: const ActivePotionEffect(
        scope: 'one_action',
        itemId: 'ITEM-0070',
        relativeDropChanceBonusPercent: 25,
        actionsRemaining: 6,
      ),
      equipment: EquipmentLoadout(
        slots: {
          ...base.equipment.slots,
          'SLOT-0008': const EquippedStack(itemId: 'ITEM-0180', quantity: 1),
        },
      ),
    );
    expect(totalRelativeDropChanceBonusPercent(db, boosted), 40);
    expect(applyRelativeDropChance(25, 40), 35);

    // 30 sits between the 25% base chance and the 35% boosted chance.
    final without = resolveActionRewards(db, base, action, seqRandom([0.30, 0]));
    final withBonus = resolveActionRewards(db, boosted, action, seqRandom([0.30, 0]));
    expect(without.loot, isEmpty);
    expect(withBonus.loot, isNotEmpty);
  });

  test('Speed does not apply to Alchemy, but Masterwork still does', () {
    final tonic = recipe('RCP-0078');
    final baseMs = (tonic.raw['Base Duration Seconds'] as num) * 1000;
    var herbs = createNewSave(db, 0).copyWith(currentLocationId: _apothecary, inventory: const []);
    herbs = addItemToInventory(herbs, 'ITEM-0031', 4);

    final speed = beginProductionQueue(
      db,
      withPotion(herbs, 'ITEM-0071'),
      'ACT-0020',
      'RCP-0078',
      1,
      0,
    );
    expect(speed.ok, isTrue);
    expect(slotStack(speed.save!, potionSlotId)?.itemId, 'ITEM-0071');
    expect(speed.save!.activePotionEffect, isNull);
    expect(speed.save!.actionDurationMs, baseMs);
    expect(isSpeedPotionItem(db, 'ITEM-0071'), isTrue);

    final masterwork = beginProductionQueue(
      db,
      withPotion(herbs, 'ITEM-0213'),
      'ACT-0020',
      'RCP-0078',
      1,
      0,
    );
    expect(masterwork.ok, isTrue);
    expect(slotStack(masterwork.save!, potionSlotId), isNull);
    expect(masterwork.save!.activePotionEffect?.itemId, 'ITEM-0213');
    expect(masterwork.save!.actionDurationMs, (baseMs * 0.85).floor());
  });

  test('unequip and swap discard leftover doses of an active potion', () {
    var save = addItemToInventory(createNewSave(db, 0), 'ITEM-0070', 4);
    final equipped = equipItemFromInventory(db, save, 'ITEM-0070');
    expect(equipped.ok, isTrue);
    save = equipped.save!.copyWith(
      activePotionEffect: const ActivePotionEffect(
        scope: 'one_action',
        itemId: 'ITEM-0070',
        relativeDropChanceBonusPercent: 25,
        actionsRemaining: 5,
      ),
    );
    final bankBefore = save.bank;
    final unequipped = unequipSlot(save, potionSlotId);
    expect(unequipped.ok, isTrue);
    expect(slotStack(unequipped.save!, potionSlotId), isNull);
    expect(unequipped.save!.activePotionEffect, isNull);
    expect(unequipped.save!.inventory.where((stack) => stack.itemId == 'ITEM-0070'), isEmpty);
    expect(unequipped.save!.bank, bankBefore);

    var swapSave = addItemToInventory(createNewSave(db, 0), 'ITEM-0070', 3);
    swapSave = addItemToInventory(swapSave, 'ITEM-0071', 2);
    final first = equipItemFromInventory(db, swapSave, 'ITEM-0070');
    expect(first.ok, isTrue);
    swapSave = first.save!.copyWith(
      activePotionEffect: const ActivePotionEffect(
        scope: 'one_action',
        itemId: 'ITEM-0070',
        relativeDropChanceBonusPercent: 25,
        actionsRemaining: 4,
      ),
    );
    final swapped = equipItemFromInventory(db, swapSave, 'ITEM-0071');
    expect(swapped.ok, isTrue);
    expect(slotStack(swapped.save!, potionSlotId)?.itemId, 'ITEM-0071');
    expect(swapped.save!.activePotionEffect, isNull);
    expect(swapped.save!.inventory.where((stack) => stack.itemId == 'ITEM-0070'), isEmpty);
  });

  test('renamed potion items keep ids so old saves still resolve them', () {
    expect(isSpeedPotionItem(db, 'ITEM-0071'), isTrue);
    expect(isSpeedPotionItem(db, 'ITEM-0070'), isFalse);
    final json = Map<String, Object?>.from(createNewSave(db, 0).toJson());
    json['inventory'] = <Object?>[
      for (final potion in _sixDosePotions)
        <String, Object?>{'itemId': potion.itemId, 'quantity': 1},
    ];
    final loaded = parseSave(json, 0);
    for (final potion in _sixDosePotions) {
      expect(
        loaded.inventory.any((stack) => stack.itemId == potion.itemId && stack.quantity == 1),
        isTrue,
        reason: potion.itemId,
      );
      expect(item(potion.itemId).internalKey, potion.key, reason: potion.itemId);
    }
  });

  test('save v64 to v65 migration keeps an active Poison potion', () {
    final json = Map<String, Object?>.from(createNewSave(db, 0).toJson());
    json['saveVersion'] = 64;
    json['activePotionEffect'] = <String, Object?>{
      'scope': 'one_combat_encounter',
      'itemId': 'ITEM-0073',
      'damageBonusPercent': null,
      'enemyMaxHpDamagePercent': 10,
      'relativeDropChanceBonusPercent': null,
      'baseDurationReductionPercent': null,
      'actionsRemaining': 6,
    };
    final migrated = parseSave(json, 0);
    expect(migrated.saveVersion, saveVersion);
    expect(migrated.activePotionEffect?.itemId, 'ITEM-0073');
    expect(migrated.activePotionEffect?.enemyMaxHpDamagePercent, 10);
    expect(migrated.activePotionEffect?.actionsRemaining, 6);
    expect(migrated.activePotionEffect?.instantHealMaxHpPercent, isNull);
    expect(applyPotionEnemyRoundDamage(1000, 1000, migrated.activePotionEffect), 900);
  });

  test('codex and tooltip effect lines are generated with 6 uses', () {
    expect(equipmentTooltipStatLines(equipment('ITEM-0439'), db), ['Heals 5%, 6 uses']);
    expect(equipmentTooltipStatLines(equipment('ITEM-0440'), db), ['Heals 3% each round, 6 uses']);
    expect(equipmentTooltipStatLines(equipment('ITEM-0441'), db), ['+10–30 damage, 6 uses']);
    expect(equipmentTooltipStatLines(equipment('ITEM-0442'), db), ['+30–90 damage, 6 uses']);
    expect(launchCodex.item('ITEM-0439')?.statLines, ['Heals 5%, 6 uses']);
    expect(launchCodex.item('ITEM-0440')?.statLines, ['Heals 3% each round, 6 uses']);
    expect(launchCodex.item('ITEM-0441')?.statLines, ['+10–30 damage, 6 uses']);
    expect(launchCodex.item('ITEM-0442')?.statLines, ['+30–90 damage, 6 uses']);
    for (final potion in _sixDosePotions) {
      final lines = equipmentTooltipStatLines(equipment(potion.itemId), db);
      expect(lines.any((line) => line.contains('6 uses')), isTrue, reason: potion.itemId);
    }
  });

  test('Willow log, Cinnamon log, and Cooked baby giant squid are hidden', () {
    expect(sourceItem('ITEM-0383').displayName, 'Willow log');
    expect(sourceItem('ITEM-0384').displayName, 'Cinnamon log');
    expect(sourceItem('ITEM-0192').displayName, 'Cooked baby giant squid');
    expect(sourceItem('ITEM-0383').retired, isTrue);
    expect(sourceItem('ITEM-0384').retired, isTrue);
    expect(sourceItem('ITEM-0192').retired, isTrue);
    expect(
      includeInCodexCatalog(
        category: sourceItem('ITEM-0383').category,
        subtype: sourceItem('ITEM-0383').subtype,
        retired: true,
      ),
      isFalse,
    );
    expect(launchCodex.items.any((row) => row.itemId == 'ITEM-0383'), isFalse);
    expect(launchCodex.items.any((row) => row.itemId == 'ITEM-0384'), isFalse);
    expect(launchCodex.items.any((row) => row.itemId == 'ITEM-0192'), isFalse);
    expect(sourceCodex.items.any((row) => row.itemId == 'ITEM-0384'), isFalse);
    expect(
      launchCodex.itemsMatching(query: 'cinnamon log').map((row) => row.itemId),
      isNot(contains('ITEM-0384')),
    );
  });

  test('five crossbreeding seeds show Crossbreeding seeds and are not retired', () {
    for (final itemId in _crossbreedingSeeds) {
      final row = sourceItem(itemId);
      expect(row.obtainedFrom, 'Crossbreeding seeds', reason: itemId);
      expect(row.retired, isNot(isTrue), reason: itemId);
      expect(
        includeInCodexCatalog(
          category: row.category,
          subtype: row.subtype,
          retired: row.retired == true,
        ),
        isTrue,
        reason: itemId,
      );
      expect(
        (sourceCodex.item(itemId)?.obtainedFrom ?? const [])
            .where((entry) => entry.kind == CodexObtainKind.note)
            .map((entry) => entry.title)
            .toList(),
        ['Crossbreeding seeds'],
        reason: itemId,
      );
    }
  });
}
