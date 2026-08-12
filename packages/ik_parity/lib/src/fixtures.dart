import 'dart:convert';
import 'dart:io';

import 'canonical_json.dart';

/// One recorded scenario: the inputs the TypeScript implementation was given
/// and the output it produced.
class ParityFixture {
  ParityFixture({
    required this.module,
    required this.name,
    required this.file,
    required this.input,
    required this.output,
  });

  final String module;
  final String name;
  final File file;
  final Object? input;
  final Object? output;

  Map<String, Object?> get inputMap => switch (input) {
    final Map<String, Object?> map => map,
    _ => throw StateError('Fixture $module/$name input is not an object'),
  };

  /// Reads a required field from the fixture input.
  T inputField<T>(String key) {
    final map = inputMap;
    if (!map.containsKey(key)) {
      throw StateError('Fixture $module/$name input is missing "$key"');
    }
    final value = map[key];
    if (value is! T) {
      throw StateError('Fixture $module/$name input "$key" is ${value.runtimeType}, expected $T');
    }
    return value;
  }

  @override
  String toString() => '$module/$name';
}

/// Repo root, found by walking up from the current directory. Dart tests run
/// with the package directory as cwd, so the fixtures live a few levels up.
Directory parityRepoRoot() {
  var dir = Directory.current.absolute;
  while (true) {
    if (Directory('${dir.path}/parity/fixtures').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'Could not find parity/fixtures above ${Directory.current.path}. '
        'Run `npm run parity:record` to generate fixtures.',
      );
    }
    dir = parent;
  }
}

/// Loads every fixture recorded for [module], recursively, sorted by name.
///
/// Fails loudly on an empty directory: a silently passing parity suite is worse
/// than no parity suite.
List<ParityFixture> loadParityFixtures(String module) {
  final dir = Directory('${parityRepoRoot().path}/parity/fixtures/$module');
  if (!dir.existsSync()) {
    throw StateError('No parity fixtures for "$module" at ${dir.path}');
  }
  final files =
      dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    throw StateError('No parity fixtures for "$module" at ${dir.path}');
  }
  return files.map((file) {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      throw StateError('Fixture ${file.path} is not a JSON object');
    }
    return ParityFixture(
      module: decoded['module'] as String? ?? module,
      name: decoded['case'] as String? ?? file.uri.pathSegments.last,
      file: file,
      input: decoded['input'],
      output: decoded['output'],
    );
  }).toList();
}

/// Returns null when [actual] matches the recorded output, otherwise a message
/// pinpointing the first differing character.
String? checkParity(ParityFixture fixture, Object? actual) {
  final expected = canonicalJson(fixture.output);
  final got = canonicalJson(actual);
  if (expected == got) return null;
  return 'Parity mismatch for $fixture (${fixture.file.path})\n'
      '${_firstDifference(expected, got)}';
}

String _firstDifference(String expected, String actual) {
  final shared = expected.length < actual.length ? expected.length : actual.length;
  var index = 0;
  while (index < shared && expected[index] == actual[index]) {
    index++;
  }
  return 'first difference at offset $index\n'
      '  expected: ${_window(expected, index)}\n'
      '  actual:   ${_window(actual, index)}';
}

String _window(String source, int index) {
  final start = index - 40 < 0 ? 0 : index - 40;
  final endLimit = index + 60;
  final end = endLimit > source.length ? source.length : endLimit;
  final prefix = start > 0 ? '...' : '';
  final suffix = end < source.length ? '...' : '';
  return '$prefix${source.substring(start, end)}$suffix';
}
