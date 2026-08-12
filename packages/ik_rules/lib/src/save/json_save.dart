/// Helpers for the one place the rules handle a save as loose JSON.
///
/// Migrations run before a save is known to match the current schema, so they
/// cannot use the generated `PlayerSave` model: a version 1 save has none of the
/// fields the model requires. They work on the decoded map instead, the same way
/// the TypeScript migrations work on a value only claimed to be a `PlayerSave`.
library;

import '../js_compat.dart';

/// A save as decoded from storage, before it is known to match the schema.
typedef SaveJson = Map<String, Object?>;

/// A mutable shallow copy, so a migration never writes through to its input.
SaveJson copySave(SaveJson save) => SaveJson.of(save);

/// A mutable copy of an entry that may itself be an object.
Object? copyEntry(Object? entry) => asObject(entry) ?? entry;

/// A mutable copy of a value that should be an object, or null when it is not.
SaveJson? asObject(Object? value) {
  if (value is Map) return SaveJson.of(value.cast<String, Object?>());
  return null;
}

/// The nested object at [key] as a mutable copy, or null when absent or not an
/// object — `save.field?` in TypeScript.
SaveJson? objectAt(SaveJson save, String key) => asObject(save[key]);

/// The array at [key] with object entries copied, or null when absent or not an
/// array — the `Array.isArray(...)` guard the migrations use.
List<Object?>? arrayAt(SaveJson save, String key) {
  final value = save[key];
  if (value is! List) return null;
  return value.map(copyEntry).toList();
}

/// `Array.isArray(save.field) ? save.field : []`, and equally `save.field ?? []`
/// for a field only ever written as an array.
List<Object?> arrayOrEmpty(SaveJson save, String key) => arrayAt(save, key) ?? <Object?>[];

/// `save.field && typeof save.field === 'object' ? save.field : {}`.
SaveJson objectOrEmpty(SaveJson save, String key) => objectAt(save, key) ?? <String, Object?>{};

/// `typeof value === 'string' ? value : null`.
String? stringOrNull(Object? value) => value is String ? value : null;

/// `stack.quantity > 0` under JavaScript coercion, so a stringified count counts.
bool isPositiveQuantity(Object? value) => jsNumber(value) > 0;
