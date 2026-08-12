import 'package:ik_parity/ik_parity.dart';
import 'package:test/test.dart';

void main() {
  test('ik_content stays free of IO', () async {
    expect(
      await forbiddenImportsIn('ik_content'),
      isEmpty,
      reason: 'ik_content must not read files itself; hosts pass the parsed database in',
    );
  });
}
