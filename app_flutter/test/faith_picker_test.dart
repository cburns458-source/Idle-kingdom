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

  testWidgets('the picker is locked at total level 99', (tester) async {
    await pumpTemple(tester, atTemple(startedCharacter(database), 99));
    await openOther(tester);

    expect(find.text('Faith'), findsOne);
    await tapFaithAction(tester, 'Choose');
    expect(find.byType(FaithPickerPanel), findsNothing);
  });

  testWidgets('the picker is open at total level 100', (tester) async {
    await pumpTemple(tester, atTemple(startedCharacter(database), 100));
    await openOther(tester);
    await tapFaithAction(tester, 'Choose');

    expect(find.byType(FaithPickerPanel), findsOne);
    final faiths = religions(database.launch);
    expect(faiths, hasLength(7));
    for (final faith in faiths) {
      final row = find.byKey(Key('faith-${faith.religionId}'));
      await tester.ensureVisible(row);
      await tester.pump();
      expect(
        find.descendant(of: find.byType(FaithPickerPanel), matching: find.text(faith.displayName)),
        findsOne,
      );
      for (final line in religionBonusSummaryLines(database.launch, faith.religionId)) {
        expect(
          find.descendant(of: find.byType(FaithPickerPanel), matching: find.text(line)),
          findsWidgets,
        );
      }
    }
  });

  testWidgets('the first pick shows as free', (tester) async {
    await pumpTemple(tester, atTemple(startedCharacter(database), 100));
    await openOther(tester);
    await tapFaithAction(tester, 'Choose');

    expect(
      find.descendant(of: find.byType(FaithPickerPanel), matching: find.text('Free')),
      findsOne,
    );
  });

  testWidgets('later picks show the gold cost', (tester) async {
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

    final cost = religionChangeGoldCost(database.launch, controller.save);
    expect(cost, greaterThan(0));
    expect(
      find.descendant(
        of: find.byType(FaithPickerPanel),
        matching: find.text(formatThousands(cost)),
      ),
      findsOne,
    );
    expect(
      find.descendant(of: find.byType(FaithPickerPanel), matching: find.text('Free')),
      findsNothing,
    );
  });

  testWidgets('cooldown blocks confirm', (tester) async {
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
    expect(
      find.descendant(of: find.byType(FaithPickerPanel), matching: find.text(remaining)),
      findsOne,
    );

    final next = find.byKey(Key('faith-${faiths[1].religionId}'));
    await tester.ensureVisible(next);
    await tester.pump();
    await tester.tap(next);
    await tester.pump();

    final confirm = tester.widget<GameButton>(
      find.descendant(
        of: find.byKey(const Key('faith-confirm')),
        matching: find.byType(GameButton),
      ),
    );
    expect(confirm.onPressed, isNull);
    await tester.tap(find.byKey(const Key('faith-confirm')));
    await tester.pump();
    expect(controller.save.religionId, faiths.first.religionId);
  });

  testWidgets('confirming the first pick follows that faith', (tester) async {
    final controller = await pumpTemple(tester, atTemple(startedCharacter(database), 100));
    await openOther(tester);
    await tapFaithAction(tester, 'Choose');

    final faith = religions(database.launch).first;
    final row = find.byKey(Key('faith-${faith.religionId}'));
    await tester.ensureVisible(row);
    await tester.pump();
    await tester.tap(row);
    await tester.pump();
    await tester.tap(find.byKey(const Key('faith-confirm')));
    await tester.pump();

    expect(controller.save.religionId, faith.religionId);
    expect(find.byType(FaithPickerPanel), findsNothing);
  });

  testWidgets('at 360px wide there is no overflow and tap targets are at least 48px', (
    tester,
  ) async {
    await pumpTemple(tester, atTemple(startedCharacter(database), 100), size: const Size(360, 740));
    await openOther(tester);
    await tapFaithAction(tester, 'Choose');

    expect(tester.takeException(), isNull);
    expect(find.byType(FaithPickerPanel), findsOne);

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

    for (final key in const [Key('faith-back'), Key('faith-confirm')]) {
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
