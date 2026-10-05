import 'package:flutter_test/flutter_test.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  test('live ticks grant 1 HP every 6 seconds out of combat', () {
    final clock = TestClock();
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentHp: 1),
      clock: clock,
    );
    addTearDown(controller.dispose);

    expect(controller.save.currentHp, 1);
    // Live play-time / HP regen batch to 1000ms, so the grant lands on a
    // 1-second tick rather than a 1ms boundary.
    clock.advance(5000);
    controller.tick();
    expect(controller.save.currentHp, 1);

    clock.advance(1000);
    controller.tick();
    expect(controller.save.currentHp, 2);

    controller.commit(controller.save.copyWith(combatEnemyId: 'ENM-0001', combatEnemyHp: 40));
    final fightingHp = controller.save.currentHp;
    clock.advance(12000);
    controller.tick();
    expect(controller.save.currentHp, fightingHp);
  });

  test('a temple blessing stays above max after live regen ticks', () {
    final clock = TestClock();
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0036', currentHp: 200),
      clock: clock,
    );
    addTearDown(controller.dispose);

    final blessed = controller.receiveBlessing();
    expect(blessed.ok, isTrue);
    final maxHp = playerMaxHp(database.launch, controller.save);
    final surplus = maxHp + (maxHp * 0.1).floor();
    expect(controller.save.currentHp, surplus);

    clock.advance(12000);
    controller.tick();
    expect(controller.save.currentHp, surplus);
  });
}
