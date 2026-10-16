import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

/// Recipe → (output item, output quantity, Base Sell Value). Only fish and meat make 2.
const Map<String, (String, int, int)> _cookingYields = {
  'RCP-0001': ('ITEM-0058', 1, 1), // Baked potato
  'RCP-0002': ('ITEM-0059', 2, 1), // Cooked perch
  'RCP-0009': ('ITEM-0066', 2, 2), // Cooked beef
  'RCP-0061': ('ITEM-0343', 1, 1), // Dried kelp
  'RCP-0007': ('ITEM-0064', 2, 1), // Cooked rabbit
  'RCP-0003': ('ITEM-0060', 2, 1), // Cooked trout
  'RCP-0076': ('ITEM-0424', 2, 1), // Cooked duck
  'RCP-0063': ('ITEM-0358', 1, 9), // Crawfish stew
  'RCP-0068': ('ITEM-0364', 1, 1), // Soup stock
  'RCP-0008': ('ITEM-0065', 2, 7), // Cooked pheasant
  'RCP-0004': ('ITEM-0061', 2, 6), // Cooked salmon
  'RCP-0012': ('ITEM-0068', 1, 19), // Pheasant stew
  'RCP-0077': ('ITEM-0425', 2, 6), // Cooked boar meat
  'RCP-0010': ('ITEM-0067', 2, 29), // Cooked venison
  'RCP-0064': ('ITEM-0359', 1, 12), // Red crab stew
  'RCP-0005': ('ITEM-0062', 2, 29), // Cooked bass
  'RCP-0013': ('ITEM-0069', 1, 108), // Venison stew
  'RCP-0067': ('ITEM-0362', 2, 4), // Cooked catfish
  'RCP-0006': ('ITEM-0063', 2, 48), // Cooked shark
  'RCP-0065': ('ITEM-0360', 1, 120), // Dungeness stew
  'RCP-0060': ('ITEM-0302', 1, 850), // Squid noodle soup
  'RCP-0044': ('ITEM-0391', 2, 53), // Cooked marlin
  'RCP-0066': ('ITEM-0361', 1, 1330), // Lobster stew
  'RCP-0070': ('ITEM-0393', 2, 99), // Cooked swordfish
};

/// Stew recipe → XP. Each stew crafts 1; XP is half of the prior 2-output values, except squid.
const Map<String, int> _stewXp = {
  'RCP-0012': 1400, // Pheasant stew (was 2800)
  'RCP-0013': 1667, // Venison stew (was 3333)
  'RCP-0060': 1850, // Squid noodle soup (chosen from ~1850; was 8000)
  'RCP-0063': 1068, // Crawfish stew (was 2135)
  'RCP-0064': 1440, // Red crab stew (was 2880)
  'RCP-0065': 1687, // Dungeness stew (was 3373)
  'RCP-0066': 2001, // Lobster stew (was 4001)
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

  test('makes 2 per craft for fish and meat only; stews, baked potato, soup stock, and dried kelp make 1', () {
    for (final MapEntry(key: recipeId, value: (itemId, quantity, _)) in _cookingYields.entries) {
      final recipe = db.recipes.firstWhere((row) => row.recipeId == recipeId);
      expect(recipe.raw['Output Item ID'], itemId, reason: recipeId);
      expect(recipe.raw['Output Quantity'], quantity, reason: recipeId);
    }
  });

  test('locks the approved cooking sell values', () {
    for (final MapEntry(key: recipeId, value: (itemId, _, value)) in _cookingYields.entries) {
      final item = db.items.firstWhere((row) => row.itemId == itemId);
      expect(item.raw['Base Sell Value'], value, reason: recipeId);
    }
  });

  test('halves stew XP and sets Squid noodle soup to 1850', () {
    for (final MapEntry(key: recipeId, value: xp) in _stewXp.entries) {
      final recipe = db.recipes.firstWhere((row) => row.recipeId == recipeId);
      expect(recipe.raw['XP Reward'], xp, reason: recipeId);
      final action = db.actions.firstWhere((row) => row.actionId == recipe.raw['Action ID']);
      expect(action.raw['XP Reward'], xp, reason: '${recipe.raw['Action ID']}');
    }
  });

  test('keeps Baked potato recipe XP at 300 when yield drops to 1', () {
    final recipe = db.recipes.firstWhere((row) => row.recipeId == 'RCP-0001');
    expect(recipe.raw['Output Quantity'], 1);
    expect(recipe.raw['XP Reward'], 300);
  });

  test('locks approved non-cooking sell values from this balance pass', () {
    expect(db.items.firstWhere((row) => row.itemId == 'ITEM-0051').raw['Base Sell Value'], 50);
    expect(db.items.firstWhere((row) => row.itemId == 'ITEM-0211').raw['Base Sell Value'], 210);
    expect(db.items.firstWhere((row) => row.itemId == 'ITEM-0040').raw['Base Sell Value'], 198);
  });

  test('a Baked potato craft grants 1, and 2 on a chef-hat proc', () {
    var save = addItemToInventory(createNewSave(db, 0), 'ITEM-0025', 1);
    final slots = Map<String, EquippedStack?>.from(save.equipment.slots)
      ..['SLOT-0003'] = const EquippedStack(itemId: chefHatItemId, quantity: 1);
    save = save.copyWith(equipment: EquipmentLoadout(slots: slots));
    final queued = beginProductionQueue(db, save, 'ACT-0017', 'RCP-0001', 1, 0);
    expect(queued.ok, isTrue);

    final missed = completeProductionCraft(db, queued.save!, 20000, _rolls([0, 0.5]));
    final hit = completeProductionCraft(db, queued.save!, 20000, _rolls([0, 0]));
    expect(missed?.outputQty, 1);
    expect(hit?.outputQty, 2);
    expect(hit?.xpGained, missed?.xpGained);
  });
}
