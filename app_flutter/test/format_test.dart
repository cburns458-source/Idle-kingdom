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

  group('formatPlayTimeMs', () {
    test('hides seconds after the first minute', () {
      expect(formatPlayTimeMs(0), '0m');
      expect(formatPlayTimeMs(45000), '45s');
      expect(formatPlayTimeMs(12 * 60000), '12m');
      expect(formatPlayTimeMs(3 * 3600000 + 12 * 60000), '3h 12m');
      expect(formatPlayTimeMs(3 * 3600000), '3h');
      expect(formatPlayTimeMs(2 * 24 * 3600000 + 5 * 3600000), '2d 5h');
      expect(formatPlayTimeMs(2 * 24 * 3600000), '2d');
    });
  });
}
