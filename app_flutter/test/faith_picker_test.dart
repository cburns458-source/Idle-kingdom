import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/game_controller.dart';
import 'package:idle_kingdoms/src/session/multiplayer_controller.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/faith_picker_panel.dart';
import 'package:idle_kingdoms/src/ui/floating_slot.dart';
import 'package:idle_kingdoms/src/ui/format.dart';
import 'package:idle_kingdoms/src/ui/location_view.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  Finder faithDock() {
    return find.ancestor(of: find.text('Faith'), matching: find.byType(DockRow));
  }

  Finder picker() => find.byType(FaithPickerPanel);

  Future<void> openOther(WidgetTester tester) async {
    final expand = find.byTooltip('Expand list');
    if (expand.evaluate().isNotEmpty) {
      await tapVisible(tester, expand);
    }
    await selectLocationBandTab(tester, 'Other');
  }

  Future<void> tapFaithAction(WidgetTester tester, String action) async {
    await tapVisible(
      tester,
      find.descendant(of: faithDock(), matching: find.bySemanticsLabel(action)),
    );
  }

  PlayerSave atTemple(PlayerSave save, int level) {
    return withTotalLevel(
      save,
      level,
    ).copyWith(currentLocationId: religionChooseLocationId(database.launch), gold: 100000);
  }

  Future<GameController> pumpTemple(
    WidgetTester tester,
    PlayerSave seed, {
    Size size = const Size(900, 2400),
  }) async {
    final controller = buildController(database, seed: seed);
    addTearDown(controller.dispose);
    final MultiplayerController net = buildMultiplayer(database);
    addTearDown(net.dispose);
    await pumpPanel(
      tester,
      LocationView(controller: controller, multiplayer: net, onOpenMap: () {}),
      size: size,
    );
    return controller;
  }

  Future<void> openFaith(WidgetTester tester, ReligionRow faith) async {
    final row = find.byKey(Key('faith-${faith.religionId}'));
    await tester.ensureVisible(row);
    await tester.pump();
    await tester.tap(row);
    await tester.pump();
  }

  test('a missing Description column reads as empty', () {
    expect(faithDescription(const ReligionRow(<String, Object?>{})), '');
    expect(faithDescription(const ReligionRow(<String, Object?>{'Description': null})), '');
    expect(faithDescription(const ReligionRow(<String, Object?>{'Description': 1})), '');
    expect(faithDescription(const ReligionRow(<String, Object?>{'Description': '  '})), '');
    expect(
      faithDescription(const ReligionRow(<String, Object?>{'Description': '  Stewards.  '})),
      'Stewards.',
    );
  });

  test('flavour lines are keyed by Display Name and match every Launch faith', () {
    final names = religions(database.launch).map((faith) => faith.displayName).toSet();
    expect(faithFlavourByName.keys.toSet(), names);
    for (final faith in religions(database.launch)) {
      final line = faithFlavourLine(faith);
      expect(line, isNotEmpty);
      expect(line, faithFlavourByName[faith.displayName]);
    }
  });

  test('every faith bonus names the amount, skill, and stat from the row', () {
    final faiths = religions(database.launch);
    expect(faiths, isNotEmpty);
    for (final faith in faiths) {
      final rows = religionBonusesFor(database.launch, faith.religionId);
      final views = faithBonusViews(database.launch, faith.religionId);
      expect(views, hasLength(rows.length));
      expect(views, isNotEmpty);
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        final view = views[i];
        final amount = jsNumberToString(jsNumber(row.raw['Bonus Value'] ?? 0));
        expect(view.amountLabel, '+$amount%');
        expect(view.statLabel, isNotEmpty);
        if (row.raw['Bonus Type'] == 'skill_drop_chance_percent') {
          expect(view.skillName, isNotNull);
          expect(view.skillName, isNot(row.raw['Reference ID']));
          expect(view.detailLine, '${view.skillName} ${view.statLabel}');
        } else {
          expect(view.skillName, isNull);
          expect(view.detailLine, view.statLabel);
        }
      }
    }
  });

  testWidgets('the picker is locked at total level 99', (tester) async {
    await pumpTemple(tester, atTemple(startedCharacter(database), 99));
    await openOther(tester);

    expect(find.text('Faith'), findsOne);
    await tapFaithAction(tester, 'Choose');
    expect(picker(), findsNothing);
  });

  testWidgets('the list shows each name and bonus, not god or description', (tester) async {
    await pumpTemple(tester, atTemple(startedCharacter(database), 100));
    await openOther(tester);
    await tapFaithAction(tester, 'Choose');

    expect(picker(), findsOne);
    expect(find.descendant(of: picker(), matching: find.text('Choose a faith…')), findsOne);

    final faiths = religions(database.launch);
    expect(faiths, hasLength(7));
    for (final faith in faiths) {
      final row = find.byKey(Key('faith-${faith.religionId}'));
      await tester.ensureVisible(row);
      await tester.pump();
      expect(find.descendant(of: picker(), matching: find.text(faith.displayName)), findsOne);
      final god = faithGodName(faith);
      if (god != null) {
        expect(find.descendant(of: picker(), matching: find.text(god)), findsNothing);
      }
      final description = faithDescription(faith);
      if (description.isNotEmpty) {
        expect(find.descendant(of: picker(), matching: find.text(description)), findsNothing);
      }
      final flavour = faithFlavourLine(faith);
      expect(flavour, isNotEmpty);
      expect(find.descendant(of: row, matching: find.text(flavour)), findsOne);
      final bonuses = faithBonusViews(database.launch, faith.religionId);
      expect(bonuses, isNotEmpty);
      expect(bonuses, hasLength(religionBonusesFor(database.launch, faith.religionId).length));
      for (final bonus in bonuses) {
        expect(find.descendant(of: row, matching: find.text(bonus.amountLabel)), findsOne);
        expect(find.descendant(of: row, matching: find.text(bonus.detailLine)), findsOne);
      }
    }

    expect(find.descendant(of: picker(), matching: find.text('Free')), findsNothing);
    expect(find.byKey(const Key('faith-choose')), findsNothing);

    final first = tester.getRect(find.byKey(Key('faith-${faiths.first.religionId}')));
    final second = tester.getRect(find.byKey(Key('faith-${faiths[1].religionId}')));
    expect(second.top - first.bottom, greaterThanOrEqualTo(12));
  });

  testWidgets('tapping a name opens its page with god, bonus, description, choose, and cost', (
    tester,
  ) async {
    await pumpTemple(tester, atTemple(startedCharacter(database), 100));
    await openOther(tester);
    await tapFaithAction(tester, 'Choose');

    final faith = religions(database.launch).first;
    await openFaith(tester, faith);

    expect(find.descendant(of: picker(), matching: find.text('Choose a faith…')), findsNothing);
    expect(find.descendant(of: picker(), matching: find.text(faith.displayName)), findsOne);
    final god = faithGodName(faith);
    if (god != null) {
      expect(find.descendant(of: picker(), matching: find.text(god)), findsOne);
    }
    for (final bonus in faithBonusViews(database.launch, faith.religionId)) {
      expect(find.descendant(of: picker(), matching: find.text(bonus.amountLabel)), findsOne);
      expect(find.descendant(of: picker(), matching: find.text(bonus.detailLine)), findsOne);
    }
    final flavour = faithFlavourLine(faith);
    expect(flavour, isNotEmpty);
    expect(find.descendant(of: picker(), matching: find.text(flavour)), findsOne);
    final description = faithDescription(faith);
    if (description.isNotEmpty) {
      expect(find.descendant(of: picker(), matching: find.text(description)), findsOne);
    }
    expect(find.descendant(of: picker(), matching: find.text('Free')), findsOne);
    expect(find.byKey(const Key('faith-choose')), findsOne);
    expect(find.byKey(const Key('faith-back')), findsOne);

    for (final other in religions(database.launch).skip(1)) {
      expect(find.descendant(of: picker(), matching: find.text(other.displayName)), findsNothing);
    }
  });

  testWidgets('Back returns to the name list', (tester) async {
    await pumpTemple(tester, atTemple(startedCharacter(database), 100));
    await openOther(tester);
    await tapFaithAction(tester, 'Choose');

    final faith = religions(database.launch).first;
    await openFaith(tester, faith);
    await tester.tap(find.byKey(const Key('faith-back')));
    await tester.pump();

    expect(find.descendant(of: picker(), matching: find.text('Choose a faith…')), findsOne);
    expect(find.byKey(const Key('faith-choose')), findsNothing);
    for (final row in religions(database.launch)) {
      expect(find.descendant(of: picker(), matching: find.text(row.displayName)), findsOne);
    }
  });

  testWidgets('the first pick shows as free on the faith page', (tester) async {
    await pumpTemple(tester, atTemple(startedCharacter(database), 100));
    await openOther(tester);
    await tapFaithAction(tester, 'Choose');
    await openFaith(tester, religions(database.launch).first);

    expect(find.descendant(of: picker(), matching: find.text('Free')), findsOne);
  });

  testWidgets('later picks show the gold cost on the faith page', (tester) async {
    final faiths = religions(database.launch);
    final controller = await pumpTemple(
      tester,
      atTemple(startedCharacter(database), 100).copyWith(
        religionId: faiths.first.religionId,
        religionChangedAt: testStartMs - religionChangeCooldownMs(database.launch),
        religionChangeCount: 1,
        religionHistory: <String>[faiths.first.religionId],
      ),
    );
    await openOther(tester);
    await tapFaithAction(tester, 'Change');
    await openFaith(tester, faiths[1]);

    final cost = religionChangeGoldCost(database.launch, controller.save);
    expect(cost, greaterThan(0));
    expect(find.descendant(of: picker(), matching: find.text(formatThousands(cost))), findsOne);
    expect(find.descendant(of: picker(), matching: find.text('Free')), findsNothing);
  });

  testWidgets('cooldown blocks choose', (tester) async {
    final faiths = religions(database.launch);
    final controller = await pumpTemple(
      tester,
      atTemple(startedCharacter(database), 100).copyWith(
        religionId: faiths.first.religionId,
        religionChangedAt: testStartMs,
        religionChangeCount: 1,
        religionHistory: <String>[faiths.first.religionId],
      ),
    );
    await openOther(tester);
    await tapFaithAction(tester, 'Change');

    final readyAt = religionChangeReadyAt(database.launch, controller.save)!;
    final remaining = formatDurationRemaining(readyAt - testStartMs);
    expect(find.descendant(of: picker(), matching: find.text(remaining)), findsNothing);

    await openFaith(tester, faiths[1]);
    expect(find.descendant(of: picker(), matching: find.text(remaining)), findsOne);

    final choose = tester.widget<GameButton>(
      find.descendant(of: find.byKey(const Key('faith-choose')), matching: find.byType(GameButton)),
    );
    expect(choose.onPressed, isNull);
    await tester.tap(find.byKey(const Key('faith-choose')));
    await tester.pump();
    expect(controller.save.religionId, faiths.first.religionId);
  });

  testWidgets('choosing the first faith follows it', (tester) async {
    final controller = await pumpTemple(tester, atTemple(startedCharacter(database), 100));
    await openOther(tester);
    await tapFaithAction(tester, 'Choose');

    final faith = religions(database.launch).first;
    await openFaith(tester, faith);
    await tester.tap(find.byKey(const Key('faith-choose')));
    await tester.pump();

    expect(controller.save.religionId, faith.religionId);
    expect(picker(), findsNothing);
  });

  testWidgets('at 360px wide there is no overflow and tap targets are at least 48px', (
    tester,
  ) async {
    await pumpTemple(tester, atTemple(startedCharacter(database), 100), size: const Size(360, 740));
    await openOther(tester);
    await tapFaithAction(tester, 'Choose');

    expect(tester.takeException(), isNull);
    expect(picker(), findsOne);

    final faiths = religions(database.launch);
    for (final faith in faiths) {
      final row = find.byKey(Key('faith-${faith.religionId}'));
      await tester.ensureVisible(row);
      await tester.pump();
      final size = tester.getSize(row);
      expect(size.width, lessThanOrEqualTo(360));
      expect(size.height, greaterThanOrEqualTo(minItemTapExtent));
    }

    final first = find.byKey(Key('faith-${faiths.first.religionId}'), skipOffstage: false);
    await tester.scrollUntilVisible(first, 48, scrollable: find.byType(Scrollable).first);
    await tester.pump();
    await tester.tap(first);
    await tester.pump();
    expect(tester.takeException(), isNull);

    for (final key in const [Key('faith-back'), Key('faith-choose')]) {
      final size = tester.getSize(find.byKey(key));
      expect(size.height, greaterThanOrEqualTo(minItemTapExtent));
      expect(size.width, greaterThanOrEqualTo(minItemTapExtent));
    }
  });
}

PlayerSave withTotalLevel(PlayerSave save, int target) {
  if (save.skills.isEmpty) {
    return save.copyWith(
      skills: <SkillProgress>[SkillProgress(skillId: 'SKL-0001', level: target, xp: 0)],
    );
  }
  final current = totalLevel(save);
  final first = save.skills.first;
  final next = first.level + (target - current);
  if (next < 1) {
    return save.copyWith(skills: <SkillProgress>[first.copyWith(level: target)]);
  }
  return save.copyWith(
    skills: <SkillProgress>[
      first.copyWith(level: next),
      ...save.skills.skip(1),
    ],
  );
}
