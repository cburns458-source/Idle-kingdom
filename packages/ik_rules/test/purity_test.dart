import 'package:ik_parity/ik_parity.dart';
import 'package:test/test.dart';

void main() {
  test('ik_rules stays headless', () async {
    expect(
      await forbiddenImportsIn('ik_rules'),
      isEmpty,
      reason: 'Platform imports leaked into ik_rules; time and randomness must be parameters',
    );
  });
}
