import 'package:flutter_test/flutter_test.dart';
import 'package:ik_content/ik_content.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  test('quiet ticks notify progress without rebuilding the shell listenable', () {
    final clock = TestClock();
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
      clock: clock,
    );
    addTearDown(controller.dispose);

    var shellNotifies = 0;
    var progressNotifies = 0;
    controller.addListener(() => shellNotifies++);
    controller.progress.addListener(() => progressNotifies++);

    clock.advance(16);
    controller.tick();
    clock.advance(16);
    controller.tick();
    clock.advance(16);
    controller.tick();

    expect(progressNotifies, 3);
    expect(shellNotifies, 0);
  });
}
