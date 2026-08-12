import 'dart:io';
import 'dart:isolate';

/// Imports that would tie a package to a host platform, breaking headless
/// testability and Dart-to-TypeScript parity replay.
const defaultForbiddenImports = <String>[
  'dart:io',
  'dart:html',
  'dart:js_interop',
  'package:flutter/',
];

/// Resolves the `lib/` directory of [package] regardless of the working
/// directory the test runner was launched from.
Future<Directory> packageLibDir(String package) async {
  final uri = await Isolate.resolvePackageUri(Uri.parse('package:$package/$package.dart'));
  if (uri == null) {
    throw StateError('Could not resolve package:$package; run `dart pub get`');
  }
  return File(uri.toFilePath()).parent;
}

/// Returns `path:line -> import` for every forbidden import found under the
/// package's `lib/`, or an empty list when the package is clean.
Future<List<String>> forbiddenImportsIn(
  String package, {
  List<String> forbidden = defaultForbiddenImports,
}) async {
  final libDir = await packageLibDir(package);
  final offenders = <String>[];
  final files =
      libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final lines = file.readAsLinesSync();
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index].trimLeft();
      if (!line.startsWith('import ') && !line.startsWith('export ')) continue;
      for (final banned in forbidden) {
        if (line.contains(banned)) {
          offenders.add('${file.path}:${index + 1} -> $banned');
        }
      }
    }
  }
  return offenders;
}
