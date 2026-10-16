import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/game_controller.dart';
import 'package:idle_kingdoms/src/session/multiplayer_controller.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/equipped_title.dart';
import 'package:idle_kingdoms/src/ui/faith_picker_panel.dart';
import 'package:idle_kingdoms/src/ui/location_view.dart';
import 'package:idle_kingdoms/src/ui/player_profile_sheet.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

const _faithNames = <String>[
  'Vaelithra',
  'Khavessa',
  'Nymorai',
  'Drazhkar',
  'Korvethan',
  'Elyndara',
  'Veyrathi',
];
const _theologianNote = 'Have chosen all 7 faiths.';

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

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  GameDatabase db() => database.launch;

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
    ).copyWith(currentLocationId: religionChooseLocationId(db()), gold: 100000);
  }

  Future<GameController> pumpTemple(WidgetTester tester, PlayerSave seed) async {
    final controller = buildController(database, seed: seed);
    addTearDown(controller.dispose);
    final MultiplayerController net = buildMultiplayer(database);
    addTearDown(net.dispose);
    await pumpPanel(
      tester,
      LocationView(controller: controller, multiplayer: net, onOpenMap: () {}),
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

  PlayerSave withEquippedFaithTitle({int faithIndex = 0}) {
    final faith = religions(db())[faithIndex];
    final titleId = faith.titleCosmeticId!;
    final base = grantCosmetic(
      startedCharacter(database),
      titleId,
    ).save.copyWith(religionId: faith.religionId, religionHistory: <String>[faith.religionId]);
    return equipCosmetic(db(), base, titleCosmeticSlotId, titleId).save!;
  }

  List<String> pickerTexts(WidgetTester tester) {
    return tester
        .widgetList<Text>(find.descendant(of: picker(), matching: find.byType(Text)))
        .map((widget) => widget.data)
        .whereType<String>()
        .where((text) => text.trim().isNotEmpty)
        .toList();
  }

  testWidgets('the Temple faith picker shows Choose a faith…, names, and bonuses', (tester) async {
    await pumpTemple(tester, atTemple(startedCharacter(database), 100));
    await openOther(tester);
    await tapFaithAction(tester, 'Choose');

    expect(picker(), findsOne);
    expect(find.descendant(of: picker(), matching: find.text('Choose a faith…')), findsOne);

    final faiths = religions(db());
    expect(faiths.map((row) => row.displayName).toSet(), _faithNames.toSet());
    final expected = <String>{'Choose a faith…', ..._faithNames};
    for (final faith in faiths) {
      expect(find.descendant(of: picker(), matching: find.text(faith.displayName)), findsOne);
      final god = faithGodName(faith);
      if (god != null) {
        expect(find.descendant(of: picker(), matching: find.text(god)), findsNothing);
      }
      final description = faithDescription(faith);
      if (description.isNotEmpty) {
        expect(find.descendant(of: picker(), matching: find.text(description)), findsNothing);
      }
      expect(faithFlavourLine(faith), '');
      expected.addAll(religionBonusSummaryLines(db(), faith.religionId));
    }
    expect(pickerTexts(tester).toSet(), expected);
  });

  testWidgets('tapping a faith name opens its page: name, god, bonus, then description', (
    tester,
  ) async {
    await pumpTemple(tester, atTemple(startedCharacter(database), 100));
    await openOther(tester);
    await tapFaithAction(tester, 'Choose');

    for (final faith in religions(db())) {
      await openFaith(tester, faith);

      expect(find.descendant(of: picker(), matching: find.text('Choose a faith…')), findsNothing);
      final header = tester.widget<Text>(
        find.descendant(of: picker(), matching: find.text(faith.displayName)),
      );
      expect(header.style?.fontSize, GameFont.l);

      final god = faithGodName(faith);
      expect(god, isNotNull);
      final description = faithDescription(faith);
      expect(description, isNotEmpty);
      final bonuses = religionBonusSummaryLines(db(), faith.religionId);
      expect(bonuses, isNotEmpty);

      final headerTop = tester
          .getTopLeft(find.descendant(of: picker(), matching: find.text(faith.displayName)))
          .dy;
      final godTop = tester.getTopLeft(find.descendant(of: picker(), matching: find.text(god!))).dy;
      final bonusTop = tester
          .getTopLeft(find.descendant(of: picker(), matching: find.text(bonuses.first)))
          .dy;
      final descriptionTop = tester
          .getTopLeft(find.descendant(of: picker(), matching: find.text(description)))
          .dy;
      expect(headerTop, lessThan(godTop));
      expect(godTop + 8, lessThan(bonusTop));
      expect(bonusTop + 8, lessThan(descriptionTop));
      expect(find.byKey(Key('faith-flavour-${faith.religionId}')), findsNothing);

      await tester.tap(find.byKey(const Key('faith-back')));
      await tester.pump();
      expect(find.descendant(of: picker(), matching: find.text('Choose a faith…')), findsOne);
    }
  });

  testWidgets('the HUD writes the equipped prefix title before the name', (tester) async {
    final save = withEquippedFaithTitle();
    final titled = displayNameWithEquippedTitle(db(), save, 'Adventurer');
    expect(titled.endsWith(' Tester'), isTrue);
    expect(titled, isNot('Tester'));
    final controller = buildController(database, seed: save);
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.text(titled), findsWidgets);
    expect(find.text('Show title on HUD'), findsNothing);
  });

  testWidgets('the HUD drops the title when unequipped, locked, or the faith changes', (
    tester,
  ) async {
    final controller = buildController(database, seed: withEquippedFaithTitle());
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    final titled = displayNameWithEquippedTitle(db(), controller.save, 'Adventurer');
    expect(find.text(titled), findsWidgets);

    controller.commit(equipCosmetic(db(), controller.save, titleCosmeticSlotId, null).save!);
    await tester.pump();
    expect(find.text(titled), findsNothing);
    expect(find.text('Tester'), findsWidgets);

    final locked = withEquippedFaithTitle().copyWith(religionId: religions(db())[1].religionId);
    expect(isFaithTitleLocked(db(), locked, religions(db()).first.titleCosmeticId), isTrue);
    expect(equippedDisplayTitle(db(), locked), isNull);
    controller.commit(locked);
    await tester.pump();
    expect(find.text(titled), findsNothing);
    expect(find.text('Tester'), findsWidgets);

    final firstSkill = withEquippedFaithTitle().skills.first;
    final ready = withEquippedFaithTitle().copyWith(
      currentLocationId: religionChooseLocationId(db()),
      gold: 100000,
      skills: <SkillProgress>[
        firstSkill.copyWith(level: firstSkill.level + (100 - totalLevel(withEquippedFaithTitle()))),
        ...withEquippedFaithTitle().skills.skip(1),
      ],
    );
    final switched = chooseReligion(db(), ready, religions(db())[1].religionId, testStartMs);
    expect(switched.ok, isTrue, reason: switched.reason);
    expect(equippedDisplayTitle(db(), switched.save!), isNull);
    controller.commit(switched.save!);
    await tester.pump();
    expect(find.text(titled), findsNothing);
    expect(find.text('Tester'), findsWidgets);
  });

  testWidgets('the HUD still shows the equipped faith title after death', (tester) async {
    final save = withEquippedFaithTitle();
    final titled = displayNameWithEquippedTitle(db(), save, 'Adventurer');
    final controller = buildController(database, seed: save);
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.text(titled), findsWidgets);
    controller.commit(applyCombatDefeat(db(), controller.save, testStartMs));
    await tester.pump();

    expect(controller.save.hasEverDied, isTrue);
    expect(find.text(titled), findsWidgets);
    expect(find.text('Tester The Undying'), findsNothing);
  });

  testWidgets('own profile shows the equipped title and has no HUD toggle', (tester) async {
    final save = withEquippedFaithTitle();
    final titled = displayNameWithEquippedTitle(db(), save, 'Tester');
    final controller = buildController(database, seed: save);
    final net = buildMultiplayer(database);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    await pumpPanel(
      tester,
      PlayerProfileSheet(controller: controller, multiplayer: net, userId: net.session!.userId),
    );
    await tester.pumpAndSettle();

    expect(find.text('Show title on HUD'), findsNothing);
    expect(find.text(titled), findsOne);
    expect(titled.endsWith(' Tester'), isTrue);
    expect(equippedDisplayTitle(db(), save)?.placement, TitlePlacement.prefix);
  });

  testWidgets("another player's profile shows their published titleCosmeticId", (tester) async {
    final save = withEquippedFaithTitle().copyWith(characterName: 'Hero');
    final titled = displayNameWithEquippedTitle(db(), save, 'Hero');
    final net = buildMultiplayer(database, signedIn: false);
    addTearDown(net.dispose);
    await net.signUp('hero@example.com', 'Hero', 'secret', save, adopt: (next, {nowMs}) {});
    expect(net.isSignedIn, isTrue, reason: net.notice);
    await net.publishRanking(save, ignoreDebounce: true);
    final heroId = net.session!.userId;
    await net.signOut(save);

    final rival = startedCharacter(database).copyWith(characterName: 'Rival');
    await net.signUp('rival@example.com', 'Rival', 'secret', rival, adopt: (next, {nowMs}) {});
    expect(net.isSignedIn, isTrue, reason: net.notice);
    final controller = buildController(database, seed: rival);
    addTearDown(controller.dispose);
    await pumpPanel(
      tester,
      PlayerProfileSheet(controller: controller, multiplayer: net, userId: heroId),
    );
    await tester.pumpAndSettle();

    expect(find.text('Show title on HUD'), findsNothing);
    expect(find.text(titled), findsOne);
    expect(
      displayNameWithPublishedTitle(db(), 'Hero', save.cosmetics.equipped[titleCosmeticSlotId]),
      titled,
    );
  });

  testWidgets('profiles show only the name when no title or an unknown id is published', (
    tester,
  ) async {
    final none = equipCosmetic(
      db(),
      startedCharacter(database).copyWith(characterName: 'Hero'),
      titleCosmeticSlotId,
      null,
    ).save!;
    expect(displayNameWithEquippedTitle(db(), none, 'Hero'), 'Hero');
    expect(displayNameWithPublishedTitle(db(), 'Hero', null), 'Hero');
    expect(displayNameWithPublishedTitle(db(), 'Hero', 'COS-9999'), 'Hero');

    final controller = buildController(database, seed: none);
    final net = buildMultiplayer(database);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    await pumpPanel(
      tester,
      PlayerProfileSheet(controller: controller, multiplayer: net, userId: net.session!.userId),
    );
    await tester.pumpAndSettle();

    expect(find.text('Show title on HUD'), findsNothing);
    expect(find.text('Hero The Undying'), findsNothing);
    expect(
      find.descendant(of: find.byType(PlayerProfileSheet), matching: find.text('Hero')),
      findsOne,
    );

    final unknown = none.copyWith(
      cosmetics: none.cosmetics.copyWith(
        equipped: <String, String?>{...none.cosmetics.equipped, titleCosmeticSlotId: 'COS-9999'},
      ),
    );
    await net.publishRanking(unknown, ignoreDebounce: true);
    expect(publishedDisplayTitle(db(), 'COS-9999'), isNull);
    expect(displayNameWithPublishedTitle(db(), 'Hero', 'COS-9999'), 'Hero');
  });

  testWidgets('Theologian deed text is exactly Have chosen all 7 faiths.', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(420, 900));
    await openChinScreen(tester, 'Log');

    await tester.tap(find.text('Hard'));
    await tester.pump();
    await tester.ensureVisible(find.text('Theologian'));
    expect(find.text('Theologian'), findsOne);
    expect(find.text(_theologianNote), findsOne);
    expect(find.textContaining('granted once'), findsNothing);
    expect(find.textContaining('Survives reload'), findsNothing);
  });

  test('content version matches between the TypeScript and Dart loaders', () {
    final tsSource = File('../src/game/data/loadDatabase.ts').readAsStringSync();
    final dartSource = File('../packages/ik_content/lib/src/load_database.dart').readAsStringSync();
    final tsVersion = RegExp(r"export const DATABASE_CONTENT_VERSION = '([^']+)'")
        .firstMatch(tsSource)!
        .group(1);
    final dartVersion = RegExp(r"const String databaseContentVersion = '([^']+)';")
        .firstMatch(dartSource)!
        .group(1);
    expect(tsVersion, databaseContentVersion);
    expect(dartVersion, databaseContentVersion);
    expect(tsVersion, dartVersion);
  });
}
