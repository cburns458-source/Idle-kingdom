import 'package:ik_net/ik_net.dart';
import 'package:test/test.dart';

void main() {
  group('plazaResponseInt', () {
    test('treats a missing field as 0', () {
      expect(plazaResponseInt(null), 0);
      expect(plazaResponseInt(<String, Object?>{}['pointsGained']), 0);
    });

    test('treats a non-numeric field as 0', () {
      expect(plazaResponseInt('25'), 0);
      expect(plazaResponseInt(true), 0);
      expect(plazaResponseInt(<Object?>[]), 0);
    });

    test('floors a numeric field', () {
      expect(plazaResponseInt(25), 25);
      expect(plazaResponseInt(25.9), 25);
      expect(plazaResponseInt(-3), -3);
    });
  });

  group('CloudSyncResult plaza fields', () {
    test('missing pointsGained and plazaPoints become 0', () {
      const failed = CloudSyncResult.failed('nope');
      expect(failed.pointsGained, 0);
      expect(failed.plazaPoints, 0);
    });
  });
}
