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
      expect(ingredientOwned(db, save, waterItemId), double.infinity);
      final tonic = recipe('RCP-0078');
      expect(maxCraftsFromMaterials(db, save, tonic), 3);
      final after = removeIngredients(db, save, recipeIngredients(tonic), 3)!;
      expect(after.inventory.where((s) => s.itemId == 'ITEM-0031'), isEmpty);
    }
    final town = base.copyWith(currentLocationId: 'LOC-0026');
    expect(ingredientOwned(db, town, kitchenScrapsItemId), 0);
    final away = base.copyWith(currentLocationId: 'LOC-0001', inventory: const []);
    expect(ingredientOwned(db, away, waterItemId), 0);
  });

  test('water is free at every kitchen, including Riverside Manor and Giant Camp', () {
    final base = createNewSave(db, 0);
    for (final loc in <String>['LOC-0023', 'LOC-0015', 'LOC-0030', 'LOC-0053', 'LOC-0049']) {
      final save = base.copyWith(currentLocationId: loc);
      expect(ingredientOwned(db, save, waterItemId), double.infinity, reason: loc);
      // Kitchen Scraps uses the same location list, so it is free here too.
      expect(ingredientOwned(db, save, kitchenScrapsItemId), double.infinity, reason: loc);
    }
    final away = base.copyWith(currentLocationId: 'LOC-0001');
    expect(ingredientOwned(db, away, waterItemId), 0);
    expect(ingredientOwned(db, away, kitchenScrapsItemId), 0);
  });

  test('finds Alchemy stations from Facilities, not a hard-coded location list', () {
    final fromFacilities = {
      for (final row in db.facilities)
        if (row.raw['Skill ID'] == 'SKL-0010')
          if (row.raw['Location ID'] is String && (row.raw['Location ID'] as String).isNotEmpty)
            row.raw['Location ID'] as String,
    };
    expect(alchemyStationLocationIds(db), fromFacilities);
    expect(fromFacilities, {'LOC-0026', 'LOC-0030'});
    final base = createNewSave(db, 0);
    expect(isAtAlchemyStation(db, base.copyWith(currentLocationId: 'LOC-0026')), isTrue);
    expect(isAtAlchemyStation(db, base.copyWith(currentLocationId: 'LOC-0023')), isFalse);
  });

  test(
    'brews at the apothecary with no water, never uses water, and refunds everything except water',
    () {
      final tonic = recipe('RCP-0078');
      var save = createNewSave(db, 0).copyWith(currentLocationId: 'LOC-0026');
      save = addItemToInventory(save, 'ITEM-0031', 5);
      save = addItemToInventory(save, waterItemId, 2);
      expect(maxCraftsFromMaterials(db, save, tonic), 5);
      expect(maxCraftsFromQueueCap(db, tonic), (24 * 3600 / 12).floor());

      final queued = beginProductionQueue(db, save, 'ACT-0020', 'RCP-0078', 3, 0);
      expect(queued.ok, isTrue);
      expect(queued.save!.inventory.firstWhere((s) => s.itemId == 'ITEM-0031').quantity, 2);
      expect(queued.save!.inventory.firstWhere((s) => s.itemId == waterItemId).quantity, 2);

      final cancelled = cancelProductionActivity(db, queued.save!);
      expect(cancelled.inventory.firstWhere((s) => s.itemId == 'ITEM-0031').quantity, 5);
      expect(cancelled.inventory.firstWhere((s) => s.itemId == waterItemId).quantity, 2);
    },
  );

  test(
    'does not treat Kitchen Scraps as free at the apothecary, and max brew counts stay herb-gated',
    () {
      final base = createNewSave(db, 0).copyWith(currentLocationId: 'LOC-0026');
      expect(ingredientOwned(db, base, kitchenScrapsItemId), 0);
      final tonic = recipe('RCP-0078');
      final withHerbs = base.copyWith(
        inventory: const [InventoryStack(itemId: 'ITEM-0031', quantity: 7)],
      );
      expect(maxCraftsFromMaterials(db, withHerbs, tonic), 7);
      expect(maxCraftsFromMaterials(db, base.copyWith(inventory: const []), tonic), 0);
    },
  );
}
