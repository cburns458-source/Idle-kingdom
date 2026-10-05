import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';

void main() {
  test('the UI type ladder is extra-small through extra-large', () {
    expect(GameFont.xs, 8);
    expect(GameFont.s, 9);
    expect(GameFont.m, 11);
    expect(GameFont.l, 12);
    expect(GameFont.xl, 15);
  });

  test('UI copy does not hard-code font sizes outside the ladder', () {
    final hits = <String>[];
    final numeric = RegExp(r'fontSize:\s*[0-9]');
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // Combat float numbers stay full size on purpose.
      if (entity.path.endsWith('action_stage.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        if (numeric.hasMatch(lines[i])) {
          hits.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}
