import 'dart:convert';

import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = filterLaunchContent(assertGameDatabaseShape(contentDatabaseJson()));
  });

  PlayerSave wear(PlayerSave save, String itemId) {
    final added = addItemToInventory(save, itemId, 1);
    final equipped = equipItemFromInventory(db, added, itemId);
    expect(equipped.ok, isTrue, reason: equipped.reason);
    return equipped.save!;
  }

  test('sells the Tome at the Wizard Shop for 314 and carries no HP or DR', () {
    final item = db.items.singleWhere((row) => row.itemId == 'ITEM-0149');
    final equipment = db.equipment.singleWhere((row) => row.equipmentId == 'EQP-0067');
    final shop = getShop(db, 'SHP-0003')!;
    expect(item.raw['Base Sell Value'], 157);
    expect(item.raw['Description'], 'Equipped spells are 20% stronger.');
    expect(equipment.hpBonus, isNull);
    expect(equipment.damageReduction, isNull);
    expect(equipment.capabilitiesEffects, contains('spell_power_pct=20'));
    expect(playerBuyPrice(db, shop, 'ITEM-0149'), 314);
  });

  test('does nothing when no spells are equipped', () {
    var save = createNewSave(db, 0);
    final baseDamage = activeSpellDamageRangeMultiplier(db, save);
    final baseDr = activeSpellDamageReductionPercent(db, save);
    final baseItems = activeSpellItemDoubleChancePercent(db, save);
    final baseGold = activeSpellGoldDoubleChancePercent(db, save);
    final baseLifesteal = activeSpellLifestealPercent(db, save);
    final baseHaste = activeSpellProductionDurationMultiplier(db, save);
    final basePathfinder = activeSpellGatheringDurationMultiplier(db, save);
    save = wear(save, 'ITEM-0149');
    expect(save.equipment.slots['SLOT-0002']?.itemId, 'ITEM-0149');
    expect(equippedSpellPowerMultiplier(db, save), 1.2);
    expect(activeSpellDamageRangeMultiplier(db, save), baseDamage);
    expect(activeSpellDamageReductionPercent(db, save), baseDr);
    expect(activeSpellItemDoubleChancePercent(db, save), baseItems);
    expect(activeSpellGoldDoubleChancePercent(db, save), baseGold);
    expect(activeSpellLifestealPercent(db, save), baseLifesteal);
    expect(activeSpellProductionDurationMultiplier(db, save), baseHaste);
    expect(activeSpellGatheringDurationMultiplier(db, save), basePathfinder);
  });

  test('raises Strength spell +10% damage to +12%', () {
    var save = createNewSave(db, 0);
    final cleared = unequipSlot(save, 'SLOT-0001');
    expect(cleared.ok, isTrue);
    save = cleared.save!;
    final base = playerDamageRange(db, save);
    save = wear(save, 'ITEM-0295');
    expect(activeSpellDamageRangeMultiplier(db, save), closeTo(1.1, 0.0001));
    final withoutTome = playerDamageRange(db, save);
    expect(withoutTome.min, (base.min * 1.1).floor());
    expect(withoutTome.max, (base.max * 1.1).floor());

    save = wear(save, 'ITEM-0149');
    expect(activeSpellDamageRangeMultiplier(db, save), closeTo(1.12, 0.0001));
    final withTome = playerDamageRange(db, save);
    expect(withTome.min, (base.min * 1.12).floor());
    expect(withTome.max, (base.max * 1.12).floor());
  });

  test('raises Iron Ward damage reduction by 20%', () {
    var save = createNewSave(db, 0);
    final gearDr = playerDamageReduction(db, save);
    save = wear(save, 'ITEM-0395');
    expect(activeSpellDamageReductionPercent(db, save), 5);
    expect(playerDamageReduction(db, save), gearDr + 5);

    save = wear(save, 'ITEM-0149');
    expect(activeSpellDamageReductionPercent(db, save), 6);
    expect(playerDamageReduction(db, save), gearDr + 6);
  });

  test('caps Tome-boosted double chance at 100%', () {
    final raw = jsonDecode(jsonEncode(contentDatabaseJson())) as Map<String, Object?>;
    final patched = filterLaunchContent(assertGameDatabaseShape(raw));
    patched.equipment.firstWhere((row) => row.itemId == 'ITEM-0297').raw['Capabilities / Effects'] =
        'spell; item_double_chance_percent:90';
    patched.equipment.firstWhere((row) => row.itemId == 'ITEM-0394').raw['Capabilities / Effects'] =
        'spell; gold_double_chance_percent:90';

    var save = addItemToInventory(createNewSave(patched, 0), 'ITEM-0297', 1);
    var equipped = equipItemFromInventory(patched, save, 'ITEM-0297');
    expect(equipped.ok, isTrue);
    save = equipped.save!;
    expect(activeSpellItemDoubleChancePercent(patched, save), 90);
    save = addItemToInventory(save, 'ITEM-0149', 1);
    equipped = equipItemFromInventory(patched, save, 'ITEM-0149');
    expect(equipped.ok, isTrue);
    save = equipped.save!;
    expect(activeSpellItemDoubleChancePercent(patched, save), 100);

    save = addItemToInventory(createNewSave(patched, 0), 'ITEM-0394', 1);
    equipped = equipItemFromInventory(patched, save, 'ITEM-0394');
    expect(equipped.ok, isTrue);
    save = equipped.save!;
    expect(activeSpellGoldDoubleChancePercent(patched, save), 90);
    save = addItemToInventory(save, 'ITEM-0149', 1);
    equipped = equipItemFromInventory(patched, save, 'ITEM-0149');
    expect(equipped.ok, isTrue);
    expect(activeSpellGoldDoubleChancePercent(patched, equipped.save!), 100);
  });

  test('raises Lifesteal 5% to 6% and still caps at 100%', () {
    var save = wear(createNewSave(db, 0), 'ITEM-0396');
    expect(activeSpellLifestealPercent(db, save), 5);
    save = wear(save, 'ITEM-0149');
    expect(activeSpellLifestealPercent(db, save), 6);

    final raw = jsonDecode(jsonEncode(contentDatabaseJson())) as Map<String, Object?>;
    final patched = filterLaunchContent(assertGameDatabaseShape(raw));
    patched.equipment.firstWhere((row) => row.itemId == 'ITEM-0396').raw['Capabilities / Effects'] =
        'spell; lifesteal_percent:90';
    save = addItemToInventory(createNewSave(patched, 0), 'ITEM-0396', 1);
    var equipped = equipItemFromInventory(patched, save, 'ITEM-0396');
    expect(equipped.ok, isTrue);
    save = equipped.save!;
    expect(activeSpellLifestealPercent(patched, save), 90);
    save = addItemToInventory(save, 'ITEM-0149', 1);
    equipped = equipItemFromInventory(patched, save, 'ITEM-0149');
    expect(equipped.ok, isTrue);
    expect(activeSpellLifestealPercent(patched, equipped.save!), 100);
  });

  test('raises Haste 10% duration cut to 12% and still floors at 0.01', () {
    var save = wear(createNewSave(db, 0), 'ITEM-0398');
    expect(activeSpellProductionDurationMultiplier(db, save), closeTo(0.9, 0.0001));
    save = wear(save, 'ITEM-0149');
    expect(activeSpellProductionDurationMultiplier(db, save), closeTo(0.88, 0.0001));

    final raw = jsonDecode(jsonEncode(contentDatabaseJson())) as Map<String, Object?>;
    final patched = filterLaunchContent(assertGameDatabaseShape(raw));
    patched.equipment.firstWhere((row) => row.itemId == 'ITEM-0398').raw['Capabilities / Effects'] =
        'spell; production_duration_reduction_percent:90';
    save = addItemToInventory(createNewSave(patched, 0), 'ITEM-0398', 1);
    var equipped = equipItemFromInventory(patched, save, 'ITEM-0398');
    expect(equipped.ok, isTrue);
    save = equipped.save!;
    expect(activeSpellProductionDurationMultiplier(patched, save), closeTo(0.1, 0.0001));
    save = addItemToInventory(save, 'ITEM-0149', 1);
    equipped = equipItemFromInventory(patched, save, 'ITEM-0149');
    expect(equipped.ok, isTrue);
    expect(activeSpellProductionDurationMultiplier(patched, equipped.save!), 0.01);
  });

  test('raises Pathfinder 10% duration cut to 12% and still floors at 0.01', () {
    var save = wear(createNewSave(db, 0), 'ITEM-0399');
    expect(activeSpellGatheringDurationMultiplier(db, save), closeTo(0.9, 0.0001));
    save = wear(save, 'ITEM-0149');
    expect(activeSpellGatheringDurationMultiplier(db, save), closeTo(0.88, 0.0001));

    final raw = jsonDecode(jsonEncode(contentDatabaseJson())) as Map<String, Object?>;
    final patched = filterLaunchContent(assertGameDatabaseShape(raw));
    patched.equipment.firstWhere((row) => row.itemId == 'ITEM-0399').raw['Capabilities / Effects'] =
        'spell; gathering_duration_reduction_percent:90';
    save = addItemToInventory(createNewSave(patched, 0), 'ITEM-0399', 1);
    var equipped = equipItemFromInventory(patched, save, 'ITEM-0399');
    expect(equipped.ok, isTrue);
    save = equipped.save!;
    expect(activeSpellGatheringDurationMultiplier(patched, save), closeTo(0.1, 0.0001));
    save = addItemToInventory(save, 'ITEM-0149', 1);
    equipped = equipItemFromInventory(patched, save, 'ITEM-0149');
    expect(equipped.ok, isTrue);
    expect(activeSpellGatheringDurationMultiplier(patched, equipped.save!), 0.01);
  });
}
