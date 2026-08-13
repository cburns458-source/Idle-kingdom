import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/ui/format.dart';

void main() {
  group('formatDurationSeconds', () {
    test('reads the way the game always has', () {
      expect(formatDurationSeconds(0), '0s');
      expect(formatDurationSeconds(-5), '0s');
      expect(formatDurationSeconds(45), '45s');
      expect(formatDurationSeconds(125), '2m 5s');
      expect(formatDurationSeconds(3725), '1h 2m 5s');
    });

    test('takes milliseconds too', () {
      expect(formatDurationMs(1500), '1s');
      expect(formatDurationMs(120000), '2m 0s');
    });
  });
}
