import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

LocationRow _loc(String id) => LocationRow({'Location ID': id});

void main() {
  test('recruits cannot pay the hall debt; member and above can', () {
    expect(canPayGuildDebt('recruit'), isFalse);
    expect(canPayGuildDebt('member'), isTrue);
    expect(canPayGuildDebt('veteran'), isTrue);
    expect(canPayGuildDebt('officer'), isTrue);
    expect(canPayGuildDebt('leader'), isTrue);
  });

  test('fifty contributed items open the boxing ring', () {
    expect(boxingRingUnlocked(0, const <String>[]), isFalse);
    expect(boxingRingUnlocked(49, const <String>[]), isFalse);
    expect(boxingRingUnlocked(50, const <String>[]), isTrue);
    expect(boxingRingUnlocked(0, const <String>[boxingRingUnlockId]), isTrue);
  });

  test('only the guild hall location offers hall services', () {
    expect(locationHasGuildHall(_loc(guildHallLocationId)), isTrue);
    expect(locationHasGuildHall(_loc(citadelPlazaId)), isFalse);
    expect(locationHasGuildHall(null), isFalse);
  });
}
