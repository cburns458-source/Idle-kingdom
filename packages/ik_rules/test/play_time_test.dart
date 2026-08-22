import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = assertGameDatabaseShape(contentDatabaseJson());
  });

  test('accrues finite positive spans and ignores the rest', () {
    final save = createNewSave(db, 0);
    expect(accruePlayTime(save, 1500).playTimeMs, 1500);
    expect(identical(accruePlayTime(save, 0), save), isTrue);
    expect(identical(accruePlayTime(save, -20), save), isTrue);
  });

  test('caps a live gap at the unattended window', () {
    const hour = 3600000;
    expect(livePlayCreditMs(1000, 24 * hour), 1000);
    expect(livePlayCreditMs(48 * hour, 24 * hour), 24 * hour);
    final save = createNewSave(db, 0).copyWith(playTimeMs: 500);
    expect(creditElapsedPlayTime(save, 48 * hour, 24 * hour).playTimeMs, 500 + 24 * hour);
  });
}
