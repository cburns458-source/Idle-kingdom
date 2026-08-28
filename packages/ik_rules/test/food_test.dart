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

  test('manual eat is refused during combat', () {
    final save = createNewSave(db, 0).copyWith(
      combatEnemyId: 'ENM-0001',
      inventory: const [InventoryStack(itemId: 'ITEM-0058', quantity: 1)],
    );
    expect(eatInventoryFood(db, save, 0).reason, 'You cannot eat during combat.');
    expect(
      eatEquippedFood(
        db,
        _withFoodAndSpells(db, foodQty: 2, gluttonyCount: 0).copyWith(combatEnemyId: 'ENM-0001'),
      ).reason,
      'You cannot eat during combat.',
    );
  });
}
