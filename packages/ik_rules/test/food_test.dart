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

  test('between-round eats follow equipped Gluttony and stop when food runs out', () {
    expect(extraFoodPerRound(db, _withFoodAndSpells(db, foodQty: 4, gluttonyCount: 0)), 0);
    final none = consumeFoodBetweenRounds(db, _withFoodAndSpells(db, foodQty: 4, gluttonyCount: 0));
    expect(none.consumed, isFalse);
    expect(none.save.equipment.slots[foodSlotId]?.quantity, 4);

    final two = consumeFoodBetweenRounds(db, _withFoodAndSpells(db, foodQty: 5, gluttonyCount: 2));
    expect(two.consumed, isTrue);
    expect(two.save.equipment.slots[foodSlotId]?.quantity, 3);

    final empty = consumeFoodBetweenRounds(
      db,
      _withFoodAndSpells(db, foodQty: 1, gluttonyCount: 4),
    );
    expect(empty.consumed, isTrue);
    expect(empty.save.equipment.slots[foodSlotId], isNull);

    final full = consumeFoodBetweenRounds(
      db,
      _withFoodAndSpells(db, foodQty: 4, gluttonyCount: 2).copyWith(currentHp: 99999),
    );
    expect(full.consumed, isFalse);
    expect(full.save.equipment.slots[foodSlotId]?.quantity, 4);
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
}
