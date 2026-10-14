import 'dart:convert';
import 'dart:io';

import 'fixtures.dart';

/// Path of the shared database, relative to the repo root.
const String contentDatabasePath = 'content/data/game-database.json';

Object? _cachedContentDatabase;

/// Rebuilds the database a fixture was recorded against.
///
/// `content` reads the same shared file the TypeScript recorder read, so both
/// sides are provably looking at identical bytes; an optional `extraRows` map
/// appends rows per table for rules the shipped content does not exercise yet.
/// `inline` and `raw` carry the database in the fixture itself, which is how
/// the small synthetic cases work.
Object? fixtureDatabaseJson(ParityFixture fixture) {
  final input = fixture.inputMap;
  final source = input['source'];
  return switch (source) {
    'content' => _withExtraRows(contentDatabaseJson(), input['extraRows']),
    'inline' => input['database'],
    'raw' => input['value'],
    _ => throw StateError('Unknown fixture database source: $source'),
  };
}

/// A copy of [database] with each table in [extraRows] extended, leaving the
/// shared cached copy untouched.
Object? _withExtraRows(Object? database, Object? extraRows) {
  if (extraRows == null) return database;
  final patched = Map<String, Object?>.of(database! as Map<String, Object?>);
  for (final entry in (extraRows as Map<String, Object?>).entries) {
    patched[entry.key] = <Object?>[
      ...?(patched[entry.key] as List<Object?>?),
      ...entry.value! as List<Object?>,
    ];
  }
  return patched;
}

/// The real shared database, decoded once per test process.
Object? contentDatabaseJson() {
  return _cachedContentDatabase ??= jsonDecode(
    File('${parityRepoRoot().path}/$contentDatabasePath').readAsStringSync(),
  );
}
