import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';
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
    test('code and noRoom survive on a failed result', () {
      const noRoom = NoRoom(slotsNeeded: 3, slotsFree: 0, reason: 'stack_full');
      final failed = CloudSyncResult.failed(
        'Inventory is full (84 slots).',
        code: 'no_room',
        noRoom: noRoom,
      );
      expect(failed.ok, isFalse);
      expect(failed.code, 'no_room');
      expect(failed.noRoom?.toJson(), noRoom.toJson());
      expect(failed.toJson()['code'], 'no_room');
      expect(failed.toJson()['noRoom'], noRoom.toJson());
    });

    test('a failure without code or noRoom leaves them unset', () {
      const failed = CloudSyncResult.failed('nope');
      expect(failed.code, isNull);
      expect(failed.noRoom, isNull);
      expect(failed.toJson().containsKey('code'), isFalse);
      expect(failed.toJson().containsKey('noRoom'), isFalse);
    });

    test('missing pointsGained and plazaPoints become 0', () {
      const failed = CloudSyncResult.failed('nope');
      expect(failed.pointsGained, 0);
      expect(failed.plazaPoints, 0);
      expect(failed.pointsSpent, 0);
    });

    test('missing pointsSpent on the wire is 0', () {
      expect(plazaResponseInt(<String, Object?>{}['pointsSpent']), 0);
    });
  });
}
