/// Base for generated row models.
///
/// A row is a typed view over the parsed JSON map, not a copy. The database uses
/// spaced column names and shops carry dynamic `Entry N ...` columns, so keeping
/// the map lets rows round-trip byte for byte and lets generic code (validation,
/// indexing) read the same values the typed accessors do.
abstract class DbRow {
  const DbRow(this.raw);

  final Map<String, Object?> raw;

  /// The row exactly as it appeared in the database.
  Map<String, Object?> toJson() => raw;

  bool has(String column) => raw.containsKey(column);

  String stringValue(String column) => _required<String>(column);

  String? stringOrNull(String column) => _optional<String>(column);

  num numberValue(String column) => _required<num>(column);

  num? numberOrNull(String column) => _optional<num>(column);

  bool boolValue(String column) => _required<bool>(column);

  bool? boolOrNull(String column) => _optional<bool>(column);

  /// Columns typed as a union of scalars in TypeScript, such as config values.
  Object? anyOrNull(String column) => raw[column];

  T _required<T>(String column) {
    final value = raw[column];
    if (value is T) return value;
    throw StateError(
      '$runtimeType column "$column" is ${value == null ? 'null' : value.runtimeType}, '
      'expected $T',
    );
  }

  T? _optional<T extends Object>(String column) {
    final value = raw[column];
    if (value == null) return null;
    if (value is T) return value;
    throw StateError('$runtimeType column "$column" is ${value.runtimeType}, expected $T?');
  }

  @override
  String toString() => '$runtimeType($raw)';
}

/// Reads [table] from the database root as raw row maps.
List<Map<String, Object?>> untypedRows(Map<String, Object?> root, String table) {
  final value = root[table];
  if (value is! List) {
    throw StateError('Database table "$table" is ${value == null ? 'missing' : 'not a list'}');
  }
  return value
      .map((row) {
        if (row is Map<String, Object?>) return row;
        throw StateError('Database table "$table" contains a non-object row');
      })
      .toList(growable: false);
}

/// Reads [table] and wraps each row with [wrap].
List<T> typedRows<T>(
  Map<String, Object?> root,
  String table,
  T Function(Map<String, Object?> raw) wrap,
) {
  return untypedRows(root, table).map(wrap).toList(growable: false);
}
