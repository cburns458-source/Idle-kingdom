import '../save/generated/save_models.dart';

bool isFavoriteStack(InventoryStack? stack) => stack?.favorite == true;

bool isFavoriteEquipped(EquippedStack? stack) => stack?.favorite == true;

/// Favorites first, otherwise original order.
///
/// The comparator carries the original index, so this does not depend on the
/// sort being stable the way the JavaScript version does.
PlayerSave sortInventoryFavoritesFirst(PlayerSave save) {
  final indexed = save.inventory.indexed.toList()
    ..sort((a, b) {
      final aFavorite = isFavoriteStack(a.$2) ? 0 : 1;
      final bFavorite = isFavoriteStack(b.$2) ? 0 : 1;
      if (aFavorite != bFavorite) return aFavorite - bFavorite;
      return a.$1 - b.$1;
    });
  return save.copyWith(inventory: indexed.map((entry) => entry.$2).toList());
}

/// Toggles the favorite flag on a bag stack, or null when the index is empty.
///
/// Unfavoriting drops the field entirely rather than storing `false`, matching
/// the TypeScript version so saved JSON stays identical.
PlayerSave? toggleInventoryFavorite(PlayerSave save, int index) {
  if (index < 0 || index >= save.inventory.length) return null;
  final inventory = save.inventory.indexed.map((entry) {
    if (entry.$1 != index) return entry.$2;
    final stack = entry.$2;
    return isFavoriteStack(stack) ? stack.copyWith(favorite: null) : stack.copyWith(favorite: true);
  }).toList();
  return sortInventoryFavoritesFirst(save.copyWith(inventory: inventory));
}
