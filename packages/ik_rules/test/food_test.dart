import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

PlayerSave _withFoodAndSpells(GameDatabase db, {required int foodQty, required int gluttonyCount}) {
  final save = createNewSave(db, 0);
  final slots = Map<String, EquippedStack?>.from(save.equipment.slots)
    ..[foodSlotId] = EquippedStack(itemId: 'ITEM-0058', quantity: foodQty);
  const spellSlots = ['SLOT-0013', 'SLOT-0014', 'SLOT-0015', 'SLOT-0016'];
  for (var i = 0; i < gluttonyCount; i += 1) {
    slots[spellSlots[i]] = const EquippedStack(itemId: 'ITEM-0312', quantity: 1);
  }
  return save.copyWith(currentHp: 900, equipment: EquipmentLoadout(slots: slots));
}

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = assertGameDatabaseShape(contentDatabaseJson());
  });

  test('soup stock is kitchen-only from water and scraps and feeds every stew', () {
    final stock = db.recipes.firstWhere((row) => row.raw['Recipe ID'] == 'RCP-0068');
    expect(stock.raw['Facility ID'], 'FAC-0001');
    expect(stock.raw['Proficiency Level'], 16);
    expect(stock.raw['Base Duration Seconds'], 12);
    expect(stock.raw['XP Reward'], 0);
    expect(stock.raw['Ingredient 1 Item ID'], 'ITEM-0365');
    expect(stock.raw['Ingredient 1 Quantity'], 1);
    expect(stock.raw['Ingredient 2 Item ID'], 'ITEM-0366');
    expect(stock.raw['Ingredient 2 Quantity'], 1);
    final away = createNewSave(db, 0);
    expect(maxCraftsFromMaterials(away, stock), 0);
    final kitchen = away.copyWith(currentLocationId: 'LOC-0023');
    expect(maxCraftsFromMaterials(kitchen, stock), double.infinity);
    expect(ingredientOwned(kitchen, 'ITEM-0365'), double.infinity);
    expect(ingredientOwned(away, 'ITEM-0365'), 0);
    for (final recipeId in <String>[
      'RCP-0012',
      'RCP-0013',
      'RCP-0060',
      'RCP-0063',
      'RCP-0064',
      'RCP-0065',
      'RCP-0066',
    ]) {
      final recipe = db.recipes.firstWhere((row) => row.raw['Recipe ID'] == recipeId);
      expect(recipe.raw['Ingredient 4 Item ID'], 'ITEM-0364');
    }
    expect(
      db.recipes.firstWhere((row) => row.raw['Recipe ID'] == 'RCP-0012').raw['XP Reward'],
      3266,
    );
    expect(db.actions.firstWhere((row) => row.actionId == 'ACN-0104').proficiencyLevel, 70);

    final queued = beginProductionQueue(
      db,
      kitchen.copyWith(
        skills: [
          for (final row in kitchen.skills)
            if (row.skillId == 'SKL-0007') row.copyWith(level: 16) else row,
        ],
      ),
      'ACT-0017',
      'RCP-0068',
      3,
      0,
    );
    expect(queued.ok, isTrue);
    expect(queued.save!.inventory, isEmpty);
    final cancelled = cancelProductionActivity(db, queued.save!);
    expect(cancelled.inventory, isEmpty);
  });

  test('Gluttony is an Arcana 30 spell that costs tuna, stew, and essence', () {
    final project = db.projects.firstWhere((row) => row.raw['Project ID'] == 'PRJ-0153');
    expect(project.displayName, 'Gluttony Spell');
    expect(project.raw['Required Skill 1 Level'], 30);
    expect(project.raw['Input 2 Item ID'], 'ITEM-0062');
    expect(project.raw['Input 2 Quantity'], 20);
    expect(project.raw['Input 3 Item ID'], 'ITEM-0069');
    expect(project.raw['Input 3 Quantity'], 20);
    expect(project.raw['Input 4 Item ID'], 'ITEM-0011');
    expect(project.raw['Input 4 Quantity'], 100);
    expect(
      db.items.any((row) => row.itemId == 'ITEM-0312' && row.displayName == 'Gluttony Spell'),
      isTrue,
    );
  });

  test('Gluttony counts extra victory eats and does not eat between rounds', () {
    expect(extraFoodPerRound(db, _withFoodAndSpells(db, foodQty: 4, gluttonyCount: 0)), 0);
    expect(extraFoodPerRound(db, _withFoodAndSpells(db, foodQty: 4, gluttonyCount: 2)), 2);
  });

  test('victory eats the usual bite plus one per Gluttony', () {
    final none = consumeFoodAfterVictory(db, _withFoodAndSpells(db, foodQty: 4, gluttonyCount: 0));
    expect(none.consumed, isTrue);
    expect(none.save.equipment.slots[foodSlotId]?.quantity, 3);

    final two = consumeFoodAfterVictory(db, _withFoodAndSpells(db, foodQty: 4, gluttonyCount: 2));
    expect(two.consumed, isTrue);
    expect(two.save.equipment.slots[foodSlotId]?.quantity, 1);

    final empty = consumeFoodAfterVictory(db, _withFoodAndSpells(db, foodQty: 2, gluttonyCount: 4));
    expect(empty.consumed, isTrue);
    expect(empty.save.equipment.slots[foodSlotId], isNull);
  });

  test('manual eat consumes from the bag and food slot, including +0 at full HP', () {
    final bag = createNewSave(
      db,
      0,
    ).copyWith(currentHp: 900, inventory: const [InventoryStack(itemId: 'ITEM-0058', quantity: 2)]);
    final healed = eatInventoryFood(db, bag, 0);
    expect(healed.ok, isTrue);
    expect(healed.healed, 40);
    expect(healed.save!.currentHp, 940);
    expect(healed.save!.inventory.single.quantity, 1);

    final full = eatInventoryFood(db, healed.save!.copyWith(currentHp: healed.save!.maxHp), 0);
    expect(full.ok, isTrue);
    expect(full.healed, 0);
    expect(full.save!.inventory, isEmpty);

    final equipped = eatEquippedFood(db, _withFoodAndSpells(db, foodQty: 2, gluttonyCount: 0));
    expect(equipped.ok, isTrue);
    expect(equipped.healed, 40);
    expect(equipped.save!.equipment.slots[foodSlotId]?.quantity, 1);
  });

  test('does not eat healing food above the eat-at threshold', () {
    final base = _withFoodAndSpells(db, foodQty: 4, gluttonyCount: 0);
    final skipped = consumeFoodAfterVictory(
      db,
      base.copyWith(
        currentHp: 800,
        settings: base.settings.copyWith(eatHealthThresholdPercent: 50),
      ),
    );
    expect(skipped.consumed, isFalse);
    expect(skipped.save.equipment.slots[foodSlotId]?.quantity, 4);

    final eaten = consumeFoodAfterVictory(db, skipped.save.copyWith(currentHp: 500));
    expect(eaten.consumed, isTrue);
    expect(eaten.save.equipment.slots[foodSlotId]?.quantity, 3);
  });

  test('skips auto-eat entirely when the toggle is off', () {
    final base = _withFoodAndSpells(db, foodQty: 4, gluttonyCount: 2);
    final skipped = consumeFoodAfterVictory(
      db,
      base.copyWith(settings: base.settings.copyWith(autoEat: false)),
    );
    expect(skipped.consumed, isFalse);
    expect(skipped.save.equipment.slots[foodSlotId]?.quantity, 4);
  });

  test('skips healing food and Gluttony extras on a one-hit clean kill', () {
    final skipped = consumeFoodAfterVictory(
      db,
      _withFoodAndSpells(db, foodQty: 4, gluttonyCount: 2),
      skipHealing: true,
    );
    expect(skipped.consumed, isFalse);
    expect(skipped.save.equipment.slots[foodSlotId]?.quantity, 4);
  });

  test('manual eat is refused during combat when auto-eat is on', () {
    final save = createNewSave(db, 0).copyWith(
      combatEnemyId: 'ENM-0001',
      combatRoundStartedAt: '2026-01-01T00:00:00.000Z',
      inventory: const [InventoryStack(itemId: 'ITEM-0058', quantity: 1)],
    );
    expect(eatInventoryFood(db, save, 0).reason, 'You cannot eat during combat.');
    expect(
      eatEquippedFood(
        db,
        _withFoodAndSpells(
          db,
          foodQty: 2,
          gluttonyCount: 0,
        ).copyWith(combatEnemyId: 'ENM-0001', combatRoundStartedAt: '2026-01-01T00:00:00.000Z'),
      ).reason,
      'You cannot eat during combat.',
    );
  });

  test('manual eat once per combat round when auto-eat is off', () {
    const round = '2026-01-01T00:00:00.000Z';
    final base = _withFoodAndSpells(db, foodQty: 3, gluttonyCount: 0);
    final save = base.copyWith(
      combatEnemyId: 'ENM-0001',
      combatRoundStartedAt: round,
      settings: base.settings.copyWith(autoEat: false),
    );
    final first = eatEquippedFood(db, save);
    expect(first.ok, isTrue);
    expect(first.save!.combatManualEatRoundStartedAt, round);
    expect(first.save!.equipment.slots[foodSlotId]?.quantity, 2);

    expect(eatEquippedFood(db, first.save!).reason, 'Already eaten this round.');

    final nextRound = eatEquippedFood(
      db,
      first.save!.copyWith(combatRoundStartedAt: '2026-01-01T00:00:04.000Z'),
    );
    expect(nextRound.ok, isTrue);
    expect(nextRound.save!.equipment.slots[foodSlotId]?.quantity, 1);
  });

  test('manual eat still works outside combat when auto-eat is off', () {
    final base = _withFoodAndSpells(db, foodQty: 2, gluttonyCount: 0);
    final eaten = eatEquippedFood(
      db,
      base.copyWith(settings: base.settings.copyWith(autoEat: false)),
    );
    expect(eaten.ok, isTrue);
    expect(eaten.save!.equipment.slots[foodSlotId]?.quantity, 1);
  });

  test('does not auto-eat after standard production or a botany harvest', () {
    final hungry = _withFoodAndSpells(db, foodQty: 4, gluttonyCount: 0);
    final queued = beginProductionQueue(
      db,
      addItemToInventory(hungry, 'ITEM-0025', 1),
      'ACT-0017',
      'RCP-0001',
      1,
      0,
    );
    expect(queued.ok, isTrue);
    final crafted = completeProductionCraft(db, queued.save!, 20_000, () => 0);
    expect(crafted, isNotNull);
    expect(crafted!.save.equipment.slots[foodSlotId]?.quantity, 4);

    final planted = plantBotanySeed(
      db,
      hungry.copyWith(
        currentLocationId: 'LOC-0001',
        inventory: const [InventoryStack(itemId: 'ITEM-0324', quantity: 1)],
        quests: const [QuestProgress(questId: 'QST-0011', status: 'completed', progress: 1)],
      ),
      'ITEM-0324',
      nowMs: 0,
      plantQuantity: 1,
    );
    expect(planted.ok, isTrue);
    final harvested = collectLocationTimer(
      db,
      planted.save!,
      'LOC-0001',
      'botany',
      nowMs: 3 * 3600 * 1000,
      random: () => 0,
    );
    expect(harvested.ok, isTrue);
    expect(harvested.save!.equipment.slots[foodSlotId]?.quantity, 4);
  });
}
