import 'package:flutter_test/flutter_test.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  testWidgets('a crafting level-up lists Leather Straps', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);
    await tester.pump();

    expect(controller.debugAddSkillLevels('SKL-0009', 9), 'Crafting is now level 10.');
    await tester.pump();
    await tester.pump();

    expect(find.text('Level 10 Crafting'), findsOne);
    expect(find.text('· Leather Straps'), findsOne);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Level 10 Crafting'), findsNothing);
  });

  testWidgets('a combat level-up does not list fight names', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);
    await tester.pump();

    expect(controller.debugAddSkillLevels(combatSkillId, 10), 'Combat is now level 11.');
    await tester.pump();
    await tester.pump();

    expect(find.text('Level 11 Combat'), findsOne);
    expect(find.textContaining('Fight '), findsNothing);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Level 11 Combat'), findsNothing);
  });
}
