import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/ui/format.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  testWidgets('a skill tile opens a numbered proficiency list', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.tap(find.text('Skills'));
    await tester.pump();
    await tester.tap(find.text('Mining'));
    await tester.pump();

    expect(find.textContaining('Mine copper ore'), findsOne);
    expect(find.textContaining(RegExp(r'^\d+\. ')), findsWidgets);
  });

  testWidgets('smithing lists material groups instead of every item', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.tap(find.text('Skills'));
    await tester.pump();
    await tester.tap(find.text('Smithing'));
    await tester.pump();

    expect(find.text('70. Tungsten items'), findsOne);
    expect(find.textContaining('Tungsten Sword'), findsNothing);
  });

  testWidgets('a skill tooltip reads total xp and what the next level needs', (tester) async {
    final save = startedCharacter(database);
    final raised = raiseSkillToMinimumLevel(save, database.launch, 'SKL-0002', 5);
    final controller = buildController(database, seed: raised.save);
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.tap(find.text('Skills'));
    await tester.pump();

    final progress = skillXpProgress(
      database.launch,
      getSkillProgress(controller.save, 'SKL-0002').xp,
    );
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(of: find.text('Mining'), matching: find.byType(Tooltip)).first,
    );

    expect(tooltip.message, contains('${formatThousands(progress.totalXp)} total xp'));
    expect(
      tooltip.message,
      contains(
        '${formatThousands(progress.toNextLevel - progress.intoLevel)} xp to '
        'level ${progress.nextLevel}',
      ),
    );
    expect(tooltip.message!.split('\n'), hasLength(2));
  });
}
