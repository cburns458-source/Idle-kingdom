import 'package:ik_parity/ik_parity.dart';
import 'package:test/test.dart';

void main() {
  test('ik_net stays transport-free', () async {
    expect(
      await forbiddenImportsIn('ik_net'),
      isEmpty,
      reason:
          'A platform import leaked into ik_net; storage, time, ids, and the '
          'network are ports the client supplies',
    );
  });
}
