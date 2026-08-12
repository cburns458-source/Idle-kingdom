import 'package:ik_parity/ik_parity.dart';
import 'package:test/test.dart';

void main() {
  test('ik_runtime stays headless', () async {
    expect(
      await forbiddenImportsIn('ik_runtime'),
      isEmpty,
      reason:
          'Platform imports leaked into ik_runtime; storage, time, and randomness '
          'are ports the client supplies',
    );
  });
}
