import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/game_controller.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/format.dart';
import 'package:idle_kingdoms/src/ui/game_image.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

const Size _skillShellSize = Size(420, 840);

Future<void> pumpSkillShell(WidgetTester tester, GameController controller) {
  return pumpShell(tester, controller, size: _skillShellSize);
}

Future<void> openSkillTile(WidgetTester tester, String name) async {
  await openChinSkills(tester);
  final tile = find.text(name);
  await tester.ensureVisible(tile);
  await tester.tap(tile);
  await tester.pump();
}

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  testWidgets('skills sit in a 4 by 4 grid with Vitality after Might', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpSkillShell(tester, controller);
    await openChinSkills(tester);

    final might = tester.getRect(find.text('Might'));
    final vitality = tester.getRect(find.text('Vitality'));
    final mining = tester.getRect(find.text('Mining'));
    final fishing = tester.getRect(find.text('Fishing'));
    final harvesting = tester.getRect(find.text('Harvesting'));
    expect((vitality.center.dy - might.center.dy).abs(), lessThan(8));
    expect(might.right, lessThan(vitality.left));
    expect((mining.center.dy - vitality.center.dy).abs(), lessThan(8));
    expect(vitality.right, lessThan(mining.left));
    expect((fishing.center.dy - mining.center.dy).abs(), lessThan(8));
    expect(mining.right, lessThan(fishing.left));
    expect(harvesting.top, greaterThan(might.bottom));

    final skillIcons = tester
        .widgetList<GameImage>(
          find.byWidgetPredicate(
            (widget) => widget is GameImage && widget.path.contains('/icons/skills/'),
          ),
        )
        .toList();
    expect(skillIcons, hasLength(16));
    expect(skillIcons.first.fit, BoxFit.contain);

    final iconRect = tester.getRect(
      find.byWidgetPredicate((widget) => widget is GameImage && widget.path.contains('skl_might')),
    );
    final tile = tester.getRect(
      find.ancestor(of: find.text('Might'), matching: find.byType(GamePanel)).first,
    );
    expect(iconRect.shortestSide, greaterThan(tile.shortestSide * 0.55));

    final bars = tester.widgetList<MeterBar>(
      find.descendant(of: find.byType(SkillsView), matching: find.byType(MeterBar)),
    );
    expect(bars, hasLength(16));
    expect(bars.every((bar) => bar.color == Palette.skillXp), isTrue);
    expect(Palette.skillXp, isNot(Palette.softGreen));
    expect(Palette.skillXp, isNot(Palette.gold));
  });

  testWidgets('a skill tile opens a numbered proficiency list', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpSkillShell(tester, controller);

    await openSkillTile(tester, 'Mining');

    expect(find.textContaining('Mine copper ore'), findsOne);
    expect(find.textContaining(RegExp(r'^\d+\. ')), findsWidgets);
  });

  testWidgets('combat lists enemy and gear tabs without quest-only fights', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpSkillShell(tester, controller);

    await openSkillTile(tester, 'Might');

    expect(find.text('Enemies'), findsNothing);
    final popup = find.byKey(const Key('game-popup'));
    expect(find.descendant(of: popup, matching: find.text('Equipment')), findsNothing);
    expect(find.descendant(of: popup, matching: find.text('Weapons')), findsOne);
    expect(find.descendant(of: popup, matching: find.text('Other')), findsOne);
    expect(find.text('Pressure the guards'), findsNothing);
    expect(
      find.descendant(of: popup, matching: find.widgetWithText(GameButton, 'Close')),
      findsNothing,
    );
    expect(find.descendant(of: popup, matching: find.byTooltip('Close')), findsOne);
    final tabs = tester.widget<Row>(
      find.ancestor(of: find.text('Weapons'), matching: find.byType(Row)).first,
    );
    expect(tabs.children.whereType<Expanded>(), hasLength(2));
  });

  testWidgets('cooking opens a recipe book that includes locked recipes', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpSkillShell(tester, controller);

    await openSkillTile(tester, 'Cooking');

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
    await pumpSkillShell(tester, controller);

    await openSkillTile(tester, 'Smithing');

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
    await pumpSkillShell(tester, controller);

    await openSkillTile(tester, 'Might');

    final popup = find.byKey(const Key('game-popup'));
    expect(find.descendant(of: popup, matching: find.text('Weapons')), findsOne);
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
    expect(find.textContaining('Wooden weapons'), findsOne);
    expect(find.textContaining('Copper weapons'), findsOne);

    await tester.tap(find.descendant(of: popup, matching: find.text('Other')));
    await tester.pump();
    expect(find.textContaining('Leather Helmet'), findsNothing);
    expect(find.textContaining('Wooden Sword'), findsNothing);
    expect(find.textContaining('Bull Horn Helmet'), findsNothing);
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

  testWidgets('Vitality lists armor tiers as equipment instead of every piece', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpSkillShell(tester, controller);

    await openSkillTile(tester, 'Vitality');
    final vitality = find.byKey(const Key('game-popup'));
    expect(find.descendant(of: vitality, matching: find.text('Enemies')), findsNothing);
    expect(find.descendant(of: vitality, matching: find.text('Weapons')), findsNothing);
    expect(find.descendant(of: vitality, matching: find.text('Equipment')), findsOne);
    await tester.tap(find.descendant(of: vitality, matching: find.text('Equipment')));
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

    await tester.tap(find.descendant(of: vitality, matching: find.text('Other')));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.textContaining('Bull Horn Helmet'),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('game-popup')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.textContaining('Bull Horn Helmet'), findsOne);
    expect(find.textContaining('Wooden Sword'), findsNothing);
    expect(find.textContaining('Cedar Bow'), findsNothing);
  });

  testWidgets('artisanry lists leather equipment on Other', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpSkillShell(tester, controller);

    await openSkillTile(tester, 'Artisanry');

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
    await pumpSkillShell(tester, controller);

    await openChinSkills(tester);

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
    await pumpSkillShell(tester, controller);

    await openChinSkills(tester);

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
