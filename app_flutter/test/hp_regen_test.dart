import 'package:flutter_test/flutter_test.dart';
import 'package:ik_content/ik_content.dart';

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
}
