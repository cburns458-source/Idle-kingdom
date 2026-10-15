import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

GameDatabase _db() => filterLaunchContent(assertGameDatabaseShape(contentDatabaseJson()));

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = _db();
  });

  PlayerSave withPotion(PlayerSave save, String itemId, [num quantity = 1]) {
    return equipStackToSlot(save, potionSlotId, itemId, quantity);
  }

  EquipmentRow equipment(String itemId) {
    return db.equipment.firstWhere((row) => row.raw['Item ID'] == itemId);
  }

  test('parses the four new alchemy potion tags', () {
    final tonic = parsePotionEffect(equipment('ITEM-0439'), 'ITEM-0439');
    expect(tonic?.instantHealMaxHpPercent, 5);
    expect(tonic?.scope, 'one_combat_encounter');

    final brew = parsePotionEffect(equipment('ITEM-0440'), 'ITEM-0440');
    expect(brew?.regenMaxHpPercentPerRound, 3);

    final draught = parsePotionEffect(equipment('ITEM-0441'), 'ITEM-0441');
    expect(draught?.damageBonusMin, 10);
    expect(draught?.damageBonusMax, 30);

    final elixir = parsePotionEffect(equipment('ITEM-0442'), 'ITEM-0442');
    expect(elixir?.damageBonusMin, 30);
    expect(elixir?.damageBonusMax, 90);
  });

  test('heals a percent of max HP on drink, capped at max HP', () {
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

    final full = beginCombatSave(
      db,
      hurt.copyWith(currentHp: started.maxHp),
      action,
      enemy,
      '2026-01-01T00:00:00.000Z',
    );
    expect(full.currentHp, full.maxHp);
  });

  test('heals a percent of max HP each combat round, capped at max HP', () {
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
    expect(round.playerHpAfterPlayer, greaterThanOrEqualTo(before));
    expect(round.playerHpAfterPlayer, lessThanOrEqualTo(started.maxHp));
  });

  test('adds a flat min/max damage bonus', () {
    final save = withPotion(createNewSave(db, 0), 'ITEM-0441');
    final baseline = playerDamageRange(db, save);
    final enemy = db.enemies.firstWhere((row) => row.raw['Enemy ID'] == 'ENM-0001');
    final action = db.actions.firstWhere((row) => row.raw['Action ID'] == 'ACN-0001');
    final started = beginCombatSave(db, save, action, enemy, '2026-01-01T00:00:00.000Z');
    expect(started.activePotionEffect?.damageBonusMin, 10);
    expect(started.activePotionEffect?.damageBonusMax, 30);
    final boosted = playerDamageRange(db, started);
    expect(boosted.min, greaterThan(baseline.min));
    expect(boosted.max, greaterThan(baseline.max));
  });

  test('applies a drop-bonus potion during combat, including to gear', () {
    final base = createNewSave(db, 0);
    final save = base.copyWith(
      activePotionEffect: const ActivePotionEffect(
        scope: 'one_combat_encounter',
        itemId: 'ITEM-0070',
        relativeDropChanceBonusPercent: 25,
      ),
      equipment: EquipmentLoadout(
        slots: {
          ...base.equipment.slots,
          'SLOT-0008': const EquippedStack(itemId: 'ITEM-0180', quantity: 1),
        },
      ),
    );
    expect(totalRelativeDropChanceBonusPercent(db, save), 40);
    expect(applyRelativeDropChance(20, 40), 28);
  });

  test('does not apply Speed to Alchemy, but still applies Masterwork', () {
    final recipe = db.recipes.firstWhere((row) => row.raw['Recipe ID'] == 'RCP-0078');
    final baseMs = jsNumber(recipe.raw['Base Duration Seconds']) * 1000;
    var herbs = createNewSave(db, 0).copyWith(currentLocationId: 'LOC-0026', inventory: const []);
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

  test('old saves with Poison active still load', () {
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
    expect(migrated.saveVersion, 65);
    expect(migrated.activePotionEffect?.enemyMaxHpDamagePercent, 10);
    expect(migrated.activePotionEffect?.instantHealMaxHpPercent, isNull);
    expect(migrated.activePotionEffect?.regenMaxHpPercentPerRound, isNull);
    expect(applyPotionEnemyRoundDamage(1000, 1000, migrated.activePotionEffect), 900);
  });

  test('generates potion tooltip lines from capability tags', () {
    expect(equipmentTooltipStatLines(equipment('ITEM-0439'), db), ['Heals 5%, 6 uses']);
    expect(equipmentTooltipStatLines(equipment('ITEM-0440'), db), ['Heals 3% each round, 6 uses']);
    expect(equipmentTooltipStatLines(equipment('ITEM-0441'), db), ['+10–30 damage, 6 uses']);
    expect(equipmentTooltipStatLines(equipment('ITEM-0442'), db), ['+30–90 damage, 6 uses']);
    expect(equipmentTooltipStatLines(equipment('ITEM-0070'), db), [
      '+25% relative Drop Chance, 6 uses',
    ]);
  });

  PlayerSave withDrunkPotion(PlayerSave save, String itemId, [num remaining = 3]) {
    return save.copyWith(
      activePotionEffect: ActivePotionEffect(
        scope: 'one_standard_production_action',
        itemId: itemId,
        relativeDropChanceBonusPercent: itemId == 'ITEM-0070' ? 25 : null,
        baseDurationReductionPercent: itemId == 'ITEM-0071' ? 10 : null,
        actionsRemaining: remaining,
      ),
    );
  }

  test('discards the active potion and leftover doses on unequip, returning nothing', () {
    var save = addItemToInventory(createNewSave(db, 0), 'ITEM-0070', 4);
    final equipped = equipItemFromInventory(db, save, 'ITEM-0070');
    expect(equipped.ok, isTrue);
    save = withDrunkPotion(equipped.save!, 'ITEM-0070', 5);
    final bankBefore = save.bank;

    final unequipped = unequipSlot(save, potionSlotId);
    expect(unequipped.ok, isTrue);
    expect(slotStack(unequipped.save!, potionSlotId), isNull);
    expect(unequipped.save!.activePotionEffect, isNull);
    expect(unequipped.save!.inventory.where((stack) => stack.itemId == 'ITEM-0070'), isEmpty);
    expect(unequipped.save!.bank, bankBefore);
  });

  test('discards the active potion when a different bottle is equipped over it', () {
    var save = addItemToInventory(createNewSave(db, 0), 'ITEM-0070', 3);
    save = addItemToInventory(save, 'ITEM-0071', 2);
    final equipped = equipItemFromInventory(db, save, 'ITEM-0070');
    expect(equipped.ok, isTrue);
    save = withDrunkPotion(equipped.save!, 'ITEM-0070', 4);
    final bankBefore = save.bank;

    final swapped = equipItemFromInventory(db, save, 'ITEM-0071');
    expect(swapped.ok, isTrue);
    expect(slotStack(swapped.save!, potionSlotId)?.itemId, 'ITEM-0071');
    expect(slotStack(swapped.save!, potionSlotId)?.quantity, 2);
    expect(swapped.save!.activePotionEffect, isNull);
    expect(swapped.save!.inventory.where((stack) => stack.itemId == 'ITEM-0070'), isEmpty);
    expect(swapped.save!.inventory.where((stack) => stack.itemId == 'ITEM-0071'), isEmpty);
    expect(swapped.save!.bank, bankBefore);
  });
}
