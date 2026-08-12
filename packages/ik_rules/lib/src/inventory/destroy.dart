import '../js_compat.dart';
import '../save/generated/save_models.dart';

/// Removes bag stacks at the given inventory indexes. Equipped items are untouched.
PlayerSave destroyInventoryIndexes(PlayerSave save, Iterable<num> indexes) {
  final remove = <int>{};
  for (final index in indexes) {
    if (jsIsInteger(index) && index >= 0 && index < save.inventory.length) {
      remove.add(index.toInt());
    }
  }
  if (remove.isEmpty) return save;
  return save.copyWith(
    inventory: save.inventory.indexed
        .where((entry) => !remove.contains(entry.$1))
        .map((entry) => entry.$2)
        .toList(),
  );
}
