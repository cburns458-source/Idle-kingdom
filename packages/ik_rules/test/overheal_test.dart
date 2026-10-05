import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  test('adds floor(max × ratio) above max', () {
    expect(overhealCeilingHp(1000, 0.05), 1050);
    expect(overhealCeilingHp(1000, 0.1), 1100);
    expect(overhealCeilingHp(1000, 0), 1000);
    expect(snapToOverhealCeiling(420, 0.1), 462);
  });

  test('heals toward a source ceiling and never cuts higher surplus', () {
    expect(healTowardCeiling(900, 1000, 320, 0.05), 1050);
    expect(healTowardCeiling(1000, 1000, 320, 0.05), 1050);
    expect(healTowardCeiling(1100, 1000, 320, 0.05), 1100);
    expect(healTowardCeiling(1000, 1000, 40, 0), 1000);
    expect(healTowardCeiling(900, 1000, 40, 0), 940);
  });

  test('reads the highest overheal_percent tag', () {
    expect(parseOverhealRatio('food_slot; consumed_after_victory'), 0);
    expect(parseOverhealRatio('food_slot; overheal_percent:5; consumed_after_victory'), 0.05);
    expect(parseOverhealRatio('overheal_percent:5; overheal_percent:10'), 0.1);
  });
}
