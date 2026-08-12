/// Test-only harness for TypeScript-to-Dart behavioral parity.
///
/// The TypeScript recorder in `tools/export_parity_fixtures.ts` drives the real
/// TS implementation over seeded scenarios and writes `parity/fixtures/**`.
/// Dart tests replay the same inputs and compare canonical JSON, so a module is
/// only considered ported once its fixtures match byte for byte.
library;

export 'src/canonical_json.dart';
export 'src/fixtures.dart';
export 'src/purity.dart';
