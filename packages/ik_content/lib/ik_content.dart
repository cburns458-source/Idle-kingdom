/// Dart view of the shared game database in `content/data/game-database.json`.
///
/// Row models are generated from the TypeScript interfaces in
/// `src/game/data/types.ts` by `tools/gen_dart_models.ts`, keeping those
/// interfaces the single schema source for both clients. Rows wrap the parsed
/// JSON rather than copying it, so unknown columns survive and a row round-trips
/// byte for byte.
library;

export 'src/db_row.dart';
export 'src/generated/rows.dart';
export 'src/indexes.dart';
export 'src/load_database.dart';
export 'src/validate.dart';
