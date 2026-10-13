import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  group('mail claim parity', () {
    for (final fixture in loadParityFixtures('mail/claim')) {
      test(fixture.name, () {
        final result = claimMailAttachments(
          saveOf(fixture),
          fixture.inputField<String>('messageId'),
          fixture.inputField<num>('nowMs'),
          databaseOf(fixture),
        );
        expect(checkParity(fixture, result.toJson()), isNull);
      });
    }
  });
}
