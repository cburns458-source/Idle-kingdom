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

    expect(controller.debugAddSkillLevels('SKL-0009', 9), 'Crafting is now level 10.');
    await tester.pumpAndSettle();

    expect(find.text('Level 10 Crafting'), findsOne);
    expect(find.text('· Leather Straps'), findsOne);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Level 10 Crafting'), findsNothing);
  });

  testWidgets('a combat level-up does not list fight names', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(controller.debugAddSkillLevels(combatSkillId, 10), 'Combat is now level 11.');
    await tester.pumpAndSettle();

    expect(find.text('Level 11 Combat'), findsOne);
    expect(find.textContaining('Fight '), findsNothing);
    expect(find.textContaining('Cow'), findsNothing);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
  });
}
