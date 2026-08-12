import 'dart:convert';
import 'dart:io';

import 'fixtures.dart';

/// Path of the shared database, relative to the repo root.
const String contentDatabasePath = 'content/data/game-database.json';

Object? _cachedContentDatabase;

/// Rebuilds the database a fixture was recorded against.
///
/// `content` reads the same shared file the TypeScript recorder read, so both
/// sides are provably looking at identical bytes. `inline` and `raw` carry the
/// database in the fixture itself, which is how the small synthetic cases work.
Object? fixtureDatabaseJson(ParityFixture fixture) {
  final input = fixture.inputMap;
  final source = input['source'];
  return switch (source) {
    'content' => contentDatabaseJson(),
    'inline' => input['database'],
    'raw' => input['value'],
    _ => throw StateError('Unknown fixture database source: $source'),
  };
}

/// The real shared database, decoded once per test process.
Object? contentDatabaseJson() {
  return _cachedContentDatabase ??= jsonDecode(
    File('${parityRepoRoot().path}/$contentDatabasePath').readAsStringSync(),
  );
}
