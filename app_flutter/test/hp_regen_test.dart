import 'package:flutter_test/flutter_test.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  test('live ticks heal 1% max HP after a minute with no damage', () {
    final clock = TestClock();
    final seed = startedCharacter(database).copyWith(currentHp: 1);
    final controller = buildController(database, seed: seed, clock: clock);
    addTearDown(controller.dispose);

    expect(controller.save.currentHp, 1);
    final maxHp = playerMaxHp(database.launch, controller.save);
    final firstHeal = naturalHpRegenHealAmount(maxHp, 0);

    // Live play-time / HP regen batch to 1000ms. Stay under the 15s foreground
    // catch-up floor so remainder carry accumulates across live ticks.
    clock.advance(10_000);
    controller.tick();
    expect(controller.save.currentHp, 1);

    for (var i = 0; i < 5; i += 1) {
      clock.advance(10_000);
      controller.tick();
    }
    expect(controller.save.currentHp, 1 + firstHeal);

    // Damage in combat resets the gate; a short window heals nothing.
    controller.commit(
      notePlayerDamaged(
        controller.save.copyWith(combatEnemyId: 'ENM-0001', combatEnemyHp: 40),
        clock.read(),
      ),
    );
    final fightingHp = controller.save.currentHp;
    clock.advance(12_000);
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

    // Same live-tick path: short steps so catch-up does not skip the surplus check.
    for (var i = 0; i < 12; i += 1) {
      clock.advance(10_000);
      controller.tick();
    }
    expect(controller.save.currentHp, surplus);
  });
}
