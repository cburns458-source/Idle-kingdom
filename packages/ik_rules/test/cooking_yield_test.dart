import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

/// SKL-04: recipe → (output item, output quantity, Base Sell Value, sell value before SKL-04).
const Map<String, (String, int, int, int)> _cookingYields = {
  'RCP-0001': ('ITEM-0058', 2, 1, 1), // Baked Potato
  'RCP-0002': ('ITEM-0059', 2, 1, 1), // Cooked Perch
  'RCP-0009': ('ITEM-0066', 2, 2, 4), // Cooked Beef
  'RCP-0061': ('ITEM-0343', 1, 1, 1), // Dried Kelp
  'RCP-0007': ('ITEM-0064', 2, 1, 3), // Cooked Rabbit
  'RCP-0003': ('ITEM-0060', 2, 1, 2), // Cooked Trout
  'RCP-0076': ('ITEM-0424', 2, 1, 2), // Cooked Duck
  'RCP-0063': ('ITEM-0358', 2, 1, 3), // Crawfish Stew
  'RCP-0068': ('ITEM-0364', 1, 1, 1), // Soup Stock
  'RCP-0008': ('ITEM-0065', 2, 7, 14), // Cooked Pheasant
  'RCP-0004': ('ITEM-0061', 2, 6, 12), // Cooked Salmon
  'RCP-0012': ('ITEM-0068', 2, 19, 39), // Pheasant Stew
  'RCP-0077': ('ITEM-0425', 2, 6, 12), // Cooked Boar Meat
  'RCP-0010': ('ITEM-0067', 2, 29, 58), // Cooked Venison
  'RCP-0064': ('ITEM-0359', 2, 12, 24), // Red Crab Stew
  'RCP-0005': ('ITEM-0062', 2, 29, 58), // Cooked Bass
  'RCP-0013': ('ITEM-0069', 2, 108, 216), // Venison Stew
  'RCP-0067': ('ITEM-0362', 2, 4, 9), // Cooked Catfish
  'RCP-0006': ('ITEM-0063', 2, 301, 602), // Cooked Shark
  'RCP-0065': ('ITEM-0360', 2, 53, 106), // Dungeness Stew
  'RCP-0060': ('ITEM-0302', 2, 415, 830), // Squid Noodle Soup
  'RCP-0044': ('ITEM-0391', 2, 53, 106), // Cooked Marlin
  'RCP-0066': ('ITEM-0361', 2, 203, 406), // Lobster Stew
  'RCP-0070': ('ITEM-0393', 2, 99, 198), // Cooked Swordfish
};

RandomFn _rolls(List<double> values) {
  var i = 0;
  return () => values[i < values.length ? i++ : values.length - 1];
}

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = assertGameDatabaseShape(contentDatabaseJson());
  });

  test('covers every Cooking recipe', () {
    final ids =
        db.recipes
            .where((row) => row.raw['Skill ID'] == 'SKL-0007')
            .map((row) => row.recipeId)
            .toList()
          ..sort();
    expect(ids, _cookingYields.keys.toList()..sort());
  });

  test('makes 2 per craft at every level, except Soup Stock and Dried Kelp at 1', () {
    for (final MapEntry(key: recipeId, value: (itemId, quantity, _, _)) in _cookingYields.entries) {
      final recipe = db.recipes.firstWhere((row) => row.recipeId == recipeId);
      expect(recipe.raw['Output Item ID'], itemId, reason: recipeId);
      expect(recipe.raw['Output Quantity'], quantity, reason: recipeId);
    }
  });

  test('halves the sell value of doubled food, rounding down to a minimum of 1', () {
    for (final MapEntry(key: recipeId, value: (itemId, quantity, value, before))
        in _cookingYields.entries) {
      expect(value, quantity == 2 ? (before ~/ 2).clamp(1, before) : before, reason: recipeId);
      final item = db.items.firstWhere((row) => row.itemId == itemId);
      expect(item.raw['Base Sell Value'], value, reason: recipeId);
    }
  });

  test('a Baked Potato craft grants 2, and 4 on a chef-hat proc', () {
    var save = addItemToInventory(createNewSave(db, 0), 'ITEM-0025', 1);
    final slots = Map<String, EquippedStack?>.from(save.equipment.slots)
      ..['SLOT-0003'] = const EquippedStack(itemId: chefHatItemId, quantity: 1);
    save = save.copyWith(equipment: EquipmentLoadout(slots: slots));
    final queued = beginProductionQueue(db, save, 'ACT-0017', 'RCP-0001', 1, 0);
    expect(queued.ok, isTrue);

    final missed = completeProductionCraft(db, queued.save!, 20000, _rolls([0, 0.5]));
    final hit = completeProductionCraft(db, queued.save!, 20000, _rolls([0, 0]));
    expect(missed?.outputQty, 2);
    expect(hit?.outputQty, 4);
    expect(hit?.xpGained, missed?.xpGained);
  });
}
