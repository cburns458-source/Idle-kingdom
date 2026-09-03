import 'generated/rows.dart';
import 'indexes.dart';
import 'validate.dart';

/// Bump when Launch content rows change, matching `DATABASE_CONTENT_VERSION` in
/// [src/game/data/loadDatabase.ts](../../../../src/game/data/loadDatabase.ts).
const String databaseContentVersion = '2026-09-03-golden-spud';

/// Path of the shared database inside `content/`. How those bytes are read is
/// the host's problem: this package stays free of IO so it can be tested
/// headlessly and reused on every platform.
const String databaseAssetPath = 'data/game-database.json';

class LoadedDatabase {
  const LoadedDatabase({
    required this.source,
    required this.launch,
    required this.sourceIndexes,
    required this.launchIndexes,
    required this.issues,
    required this.needsDataCount,
  });

  /// Full source database, never filtered.
  final GameDatabase source;

  /// Launch-phase view used for runtime content selection.
  final GameDatabase launch;

  final DatabaseIndexes sourceIndexes;
  final DatabaseIndexes launchIndexes;
  final List<ValidationIssue> issues;
  final int needsDataCount;
}

/// Validates [raw] and builds the runtime views.
///
/// Throws [DatabaseShapeException] when a table is missing and
/// [DatabaseValidationException] when validation finds errors, with the same
/// message the TypeScript loader produces.
LoadedDatabase prepareDatabase(Object? raw) {
  final source = assertGameDatabaseShape(raw);
  final issues = validateDatabase(source);
  final errors = issues.where((issue) => issue.isError).toList(growable: false);
  if (errors.isNotEmpty) {
    final summary = errors
        .take(5)
        .map((issue) => '${issue.table ?? 'root'}: ${issue.message}')
        .join('; ');
    throw DatabaseValidationException(
      'Database validation failed (${errors.length} error(s)): $summary',
      errors,
    );
  }

  final launch = filterLaunchContent(source);
  return LoadedDatabase(
    source: source,
    launch: launch,
    sourceIndexes: buildIndexes(source),
    launchIndexes: buildIndexes(launch),
    issues: issues,
    needsDataCount: countNeedsData(source),
  );
}
