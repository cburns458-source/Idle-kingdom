import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = assertGameDatabaseShape(contentDatabaseJson());
  });

  RecipeRow recipe(String id) => db.recipes.firstWhere((row) => row.raw['Recipe ID'] == id);

  test('every potion recipe lists Water x1', () {
    for (final id in <String>[
      'RCP-0040', 'RCP-0041', 'RCP-0043', 'RCP-0053', 'RCP-0054', 'RCP-0055', //
      'RCP-0056', 'RCP-0059', 'RCP-0078', 'RCP-0079', 'RCP-0080', 'RCP-0081',
    ]) {
      final ingredients = recipeIngredients(recipe(id));
      expect(
        ingredients.any((i) => i.itemId == waterItemId && i.quantity == 1),
        isTrue,
        reason: id,
      );
    }
  });

  test('water is free and unconsumed at both apothecaries, but not elsewhere', () {
    final base = createNewSave(db, 0);
    for (final loc in <String>['LOC-0026', 'LOC-0030']) {
      final save = base.copyWith(
        currentLocationId: loc,
        inventory: const [InventoryStack(itemId: 'ITEM-0031', quantity: 3)],
      );
      expect(ingredientOwned(save, waterItemId), double.infinity);
      final tonic = recipe('RCP-0078');
      expect(maxCraftsFromMaterials(save, tonic), 3);
      final after = removeIngredients(save, recipeIngredients(tonic), 3)!;
      expect(after.inventory.where((s) => s.itemId == 'ITEM-0031'), isEmpty);
    }
    final town = base.copyWith(currentLocationId: 'LOC-0026');
    expect(ingredientOwned(town, kitchenScrapsItemId), 0);
    final away = base.copyWith(currentLocationId: 'LOC-0001', inventory: const []);
    expect(ingredientOwned(away, waterItemId), 0);
  });

  test('water is free at every kitchen, including Riverside Manor and Giant Camp', () {
    final base = createNewSave(db, 0);
    for (final loc in <String>['LOC-0023', 'LOC-0015', 'LOC-0030', 'LOC-0053', 'LOC-0049']) {
      final save = base.copyWith(currentLocationId: loc);
      expect(ingredientOwned(save, waterItemId), double.infinity, reason: loc);
      // Kitchen Scraps uses the same location list, so it is free here too.
      expect(ingredientOwned(save, kitchenScrapsItemId), double.infinity, reason: loc);
    }
    final away = base.copyWith(currentLocationId: 'LOC-0001');
    expect(ingredientOwned(away, waterItemId), 0);
    expect(ingredientOwned(away, kitchenScrapsItemId), 0);
  });
}
