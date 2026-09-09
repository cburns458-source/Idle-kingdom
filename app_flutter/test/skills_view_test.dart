import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
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

    await tester.tap(find.text('Character'));
    await tester.pump();
    await tester.tap(find.widgetWithText(GameButton, 'Skills'));
    await tester.pump();
    await tester.tap(find.text('Mining'));
    await tester.pump();

    expect(find.textContaining('Mine copper ore'), findsOne);
    expect(find.textContaining(RegExp(r'^\d+\. ')), findsWidgets);
  });

  testWidgets('combat lists enemy and gear tabs without quest-only fights', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.tap(find.text('Character'));
    await tester.pump();
    await tester.tap(find.widgetWithText(GameButton, 'Skills'));
    await tester.pump();
    await tester.tap(find.text('Combat'));
    await tester.pump();

    expect(find.text('Enemies'), findsOne);
    final popup = find.byKey(const Key('game-popup'));
    expect(find.descendant(of: popup, matching: find.text('Equipment')), findsOne);
    expect(find.descendant(of: popup, matching: find.text('Weapons')), findsOne);
    expect(find.descendant(of: popup, matching: find.text('Other')), findsOne);
    expect(find.text('Pressure the guards'), findsNothing);
    expect(
      find.descendant(of: popup, matching: find.widgetWithText(GameButton, 'Close')),
      findsNothing,
    );
    expect(find.descendant(of: popup, matching: find.byTooltip('Close')), findsOne);
    final tabs = tester.widget<Row>(
      find.ancestor(of: find.text('Enemies'), matching: find.byType(Row)).first,
    );
    expect(tabs.children.whereType<Expanded>(), hasLength(4));
  });

  testWidgets('cooking opens a recipe book that includes locked recipes', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.tap(find.text('Character'));
    await tester.pump();
    await tester.tap(find.widgetWithText(GameButton, 'Skills'));
    await tester.pump();
    await tester.tap(find.text('Cooking'));
    await tester.pump();

    final popup = find.byKey(const Key('game-popup'));
    expect(
      find.descendant(of: popup, matching: find.widgetWithText(GameButton, 'Recipe book')),
      findsOne,
    );
    expect(
      tester.widget<GameButton>(find.widgetWithText(GameButton, 'Recipe book')).compact,
      isTrue,
    );
    expect(
      find.descendant(of: popup, matching: find.widgetWithText(GameButton, 'Close')),
      findsNothing,
    );
    expect(find.descendant(of: popup, matching: find.byTooltip('Close')), findsOne);
    await tester.tap(find.text('Recipe book'));
    await tester.pump();
    expect(find.textContaining('Unlocks at Cooking'), findsWidgets);
    await tester.tap(find.widgetWithText(GameButton, 'Other').last);
    await tester.pump();
    expect(find.textContaining('Baked potato'), findsWidgets);
  });

  testWidgets('smithing lists material groups instead of every item', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.tap(find.text('Character'));
    await tester.pump();
    await tester.tap(find.widgetWithText(GameButton, 'Skills'));
    await tester.pump();
    await tester.tap(find.text('Smithing'));
    await tester.pump();

    await tester.scrollUntilVisible(
      find.textContaining('70. Titanium items'),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('game-popup')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.textContaining('70. Titanium items'), findsOne);
    expect(find.textContaining('60. Tungsten items'), findsOne);
    expect(find.textContaining('Tungsten Sword'), findsNothing);
    expect(find.textContaining('Titanium Sword'), findsNothing);
  });

  testWidgets('combat lists armor tiers as equipment instead of every piece', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.tap(find.text('Character'));
    await tester.pump();
    await tester.tap(find.widgetWithText(GameButton, 'Skills'));
    await tester.pump();
    await tester.tap(find.text('Combat'));
    await tester.pump();

    final popup = find.byKey(const Key('game-popup'));
    await tester.tap(find.descendant(of: popup, matching: find.text('Equipment')));
    await tester.pump();
    expect(find.textContaining('Leather equipment'), findsOne);
    await tester.scrollUntilVisible(
      find.textContaining('Tungsten equipment'),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('game-popup')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.textContaining('Tungsten equipment'), findsOne);
    expect(find.textContaining('Tungsten Helmet'), findsNothing);
    expect(find.textContaining('Tungsten Shield'), findsNothing);
    expect(find.textContaining('Tungsten Sword'), findsNothing);

    await tester.tap(find.descendant(of: popup, matching: find.text('Weapons')));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.textContaining('Tungsten weapons'),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('game-popup')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.textContaining('Tungsten weapons'), findsOne);
    expect(find.textContaining('Tungsten Sword'), findsNothing);
    expect(find.textContaining('Tungsten Shield'), findsNothing);
    expect(find.textContaining('Wooden weapons'), findsNothing);

    await tester.tap(find.descendant(of: popup, matching: find.text('Other')));
    await tester.pump();
    expect(find.textContaining('Leather Helmet'), findsNothing);
    expect(find.textContaining('Wooden Sword'), findsOne);
    await tester.scrollUntilVisible(
      find.textContaining('Bull Horn Helmet'),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('game-popup')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.textContaining('Bull Horn Helmet'), findsOne);
    await tester.scrollUntilVisible(
      find.textContaining('Cedar Bow'),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('game-popup')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.textContaining('Cedar Bow'), findsOne);
    expect(find.textContaining('Boar Spear'), findsOne);
  });

  testWidgets('artisanry lists leather equipment on Other', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.tap(find.text('Character'));
    await tester.pump();
    await tester.tap(find.widgetWithText(GameButton, 'Skills'));
    await tester.pump();
    await tester.tap(find.text('Artisanry'));
    await tester.pump();

    final popup = find.byKey(const Key('game-popup'));
    await tester.tap(find.descendant(of: popup, matching: find.text('Other')));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.textContaining('Leather equipment'),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('game-popup')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.textContaining('Leather equipment'), findsOne);
    expect(find.textContaining('Leather Helmet'), findsNothing);
    expect(find.textContaining('Leather Gloves'), findsNothing);
  });

  testWidgets('a skill tooltip reads total xp and what the next level needs', (tester) async {
    final save = startedCharacter(database);
    final raised = raiseSkillToMinimumLevel(save, database.launch, 'SKL-0002', 5);
    final controller = buildController(database, seed: raised.save);
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.tap(find.text('Character'));
    await tester.pump();
    await tester.tap(find.widgetWithText(GameButton, 'Skills'));
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

  testWidgets('a capped skill shows its level, not mastered', (tester) async {
    final last = database.launch.xpCurve.last;
    final seed = startedCharacter(database);
    final first = seed.skills.first;
    final name = database.launch.skills
        .firstWhere((row) => row.skillId == first.skillId)
        .displayName;
    final capXp = last.totalXpAtLevel + (last.xpToNextLevel ?? 0);
    final controller = buildController(
      database,
      seed: seed.copyWith(
        skills: <SkillProgress>[
          first.copyWith(level: last.level, xp: capXp),
          ...seed.skills.skip(1),
        ],
      ),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.tap(find.text('Character'));
    await tester.pump();
    await tester.tap(find.widgetWithText(GameButton, 'Skills'));
    await tester.pump();

    expect(find.text('Mastered'), findsNothing);
    expect(find.textContaining('mastered'), findsNothing);
    expect(find.text('Max'), findsNothing);
    expect(find.text('Lv ${last.level}'), findsOne);

    final tooltip = tester.widget<Tooltip>(
      find.ancestor(of: find.text(name), matching: find.byType(Tooltip)).first,
    );
    expect(tooltip.message, isNot(contains('mastered')));
    expect(tooltip.message, isNot(contains('Mastered')));
    expect(tooltip.message, contains('${formatThousands(capXp)} total xp'));
  });
}
