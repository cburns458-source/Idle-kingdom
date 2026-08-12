import '../save/generated/save_models.dart';
import 'recipes.dart';

/// Spends ingredients for `crafts` repetitions, or null when any are missing.
///
/// Emptied stacks leave the bag, which is why callers must re-resolve inventory
/// indexes afterwards.
PlayerSave? removeIngredients(
  PlayerSave save,
  List<RecipeIngredient> ingredients, [
  num crafts = 1,
]) {
  if (crafts <= 0) return save;
  final inventory = [...save.inventory];
  for (final ingredient in ingredients) {
    final need = ingredient.quantity * crafts;
    final index = inventory.indexWhere((entry) => entry.itemId == ingredient.itemId);
    if (index < 0 || inventory[index].quantity < need) return null;
    inventory[index] = inventory[index].copyWith(quantity: inventory[index].quantity - need);
  }
  return save.copyWith(inventory: inventory.where((stack) => stack.quantity > 0).toList());
}
