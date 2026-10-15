import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/ui/equipped_title.dart';
import 'package:idle_kingdoms/src/ui/player_profile_sheet.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  PlayerSave withEquippedFaithTitle({int faithIndex = 0}) {
    final faith = religions(database.launch)[faithIndex];
    final titleId = faith.titleCosmeticId!;
    final base = grantCosmetic(
      startedCharacter(database),
      titleId,
    ).save.copyWith(religionId: faith.religionId, religionHistory: <String>[faith.religionId]);
    return equipCosmetic(database.launch, base, titleCosmeticSlotId, titleId).save!;
  }

  testWidgets('a new character carries The Undying on the HUD', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(controller.save.hasEverDied, isFalse);
    expect(find.text('Tester The Undying'), findsWidgets);
    expect(find.text('Show title on HUD'), findsNothing);
  });

  testWidgets('being beaten in the world costs the title for good', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    controller.commit(applyCombatDefeat(database.launch, controller.save, testStartMs));
    await tester.pump();

    expect(controller.save.hasEverDied, isTrue);
    expect(find.text('Tester The Undying'), findsNothing);
    expect(find.text('Tester'), findsWidgets);

    // The loss is written down, so reloading does not hand the title back.
    final reloaded = PlayerSave.fromJson(controller.save.toJson());
    expect(reloaded.hasEverDied, isTrue);
    expect(titleForSave(reloaded), isNull);
  });

  test('an arena loss leaves the title alone', () {
    final save = startedCharacter(database);
    expect(titleForSave(save)?.text, 'The Undying');

    // PvP resolves without touching the save's world state, so the title holds.
    final afterArena = save.copyWith(currentHp: 1);
    expect(afterArena.hasEverDied, isFalse);
    expect(titleForSave(afterArena)?.text, 'The Undying');
  });

  test('an existing save keeps the title through the migration', () {
    final save = startedCharacter(database);
    final old = save.toJson()
      ..['saveVersion'] = 26
      ..remove('hasEverDied');

    final migrated = PlayerSave.fromJson(migrateSaveJson(old, testStartMs));
    expect(migrated.saveVersion, saveVersion);
    expect(migrated.hasEverDied, isFalse);
    expect(titleForSave(migrated)?.text, 'The Undying');
  });

  test('a title reads on whichever side its format asks for', () {
    expect(nameWithTitle('Rowan', undyingTitle), 'Rowan The Undying');
    expect(
      nameWithTitle('Rowan', const PlayerTitle(text: 'Sir', placement: TitlePlacement.prefix)),
      'Sir Rowan',
    );
    expect(nameWithTitle('Rowan', null), 'Rowan');
  });

  test('an unnamed save is never given a title', () {
    final nameless = startedCharacter(database).copyWith(characterName: null);
    expect(displayNameForSave(nameless, 'Adventurer'), 'Adventurer');
    expect(displayNameWithEquippedTitle(database.launch, nameless, 'Adventurer'), 'Adventurer');
  });

  test('unequipping The Undying hides it from the name', () {
    final save = startedCharacter(database);
    final unequipped = equipCosmetic(database.launch, save, titleCosmeticSlotId, null);
    expect(unequipped.ok, isTrue);
    expect(titleForSave(unequipped.save!), isNull);
    expect(displayNameForSave(unequipped.save!, 'Adventurer'), 'Tester');
    expect(displayNameWithEquippedTitle(database.launch, unequipped.save!, 'Adventurer'), 'Tester');
  });

  test('an equipped faith title sits before the name', () {
    final save = withEquippedFaithTitle();
    final faith = religions(database.launch).first;
    final title = equippedDisplayTitle(database.launch, save);
    expect(title?.placement, TitlePlacement.prefix);
    expect(title?.text, isNotEmpty);
    expect(
      displayNameWithEquippedTitle(database.launch, save, 'Adventurer'),
      '${title!.text} Tester',
    );
    expect(religionIdForTitleCosmetic(database.launch, faith.titleCosmeticId), faith.religionId);
  });

  test('a locked or left faith title is hidden', () {
    final save = withEquippedFaithTitle();
    final titleId = religions(database.launch).first.titleCosmeticId!;
    final locked = save.copyWith(religionId: religions(database.launch)[1].religionId);
    expect(isFaithTitleLocked(database.launch, locked, titleId), isTrue);
    expect(equippedDisplayTitle(database.launch, locked), isNull);
    expect(displayNameWithEquippedTitle(database.launch, locked, 'Adventurer'), 'Tester');

    final firstSkill = save.skills.first;
    final switched = chooseReligion(
      database.launch,
      save.copyWith(
        currentLocationId: religionChooseLocationId(database.launch),
        gold: 100000,
        skills: <SkillProgress>[
          firstSkill.copyWith(level: firstSkill.level + (100 - totalLevel(save))),
          ...save.skills.skip(1),
        ],
      ),
      religions(database.launch)[1].religionId,
      testStartMs,
    );
    expect(switched.ok, isTrue);
    expect(equippedDisplayTitle(database.launch, switched.save!), isNull);
    expect(displayNameWithEquippedTitle(database.launch, switched.save!, 'Adventurer'), 'Tester');
  });

  testWidgets('the HUD writes the prefix title before the name', (tester) async {
    final save = withEquippedFaithTitle();
    final titled = displayNameWithEquippedTitle(database.launch, save, 'Adventurer');
    final controller = buildController(database, seed: save);
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.text(titled), findsWidgets);
    expect(titled, isNot('Tester'));
    expect(titled.endsWith(' Tester'), isTrue);
  });

  testWidgets('unequipping hides the title on the HUD', (tester) async {
    final controller = buildController(database, seed: withEquippedFaithTitle());
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    final titled = displayNameWithEquippedTitle(database.launch, controller.save, 'Adventurer');
    expect(find.text(titled), findsWidgets);

    controller.commit(
      equipCosmetic(database.launch, controller.save, titleCosmeticSlotId, null).save!,
    );
    await tester.pump();

    expect(find.text(titled), findsNothing);
    expect(find.text('Tester'), findsWidgets);
  });

  testWidgets('the player profile always shows the equipped title', (tester) async {
    final save = withEquippedFaithTitle();
    final titled = displayNameWithEquippedTitle(database.launch, save, 'Tester');
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
    expect(find.text('Tester The Undying'), findsNothing);
  });

  testWidgets('the player profile shows nothing extra when no title is equipped', (tester) async {
    final unequipped = equipCosmetic(
      database.launch,
      startedCharacter(database),
      titleCosmeticSlotId,
      null,
    ).save!;
    final controller = buildController(database, seed: unequipped);
    final net = buildMultiplayer(database);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    await pumpPanel(
      tester,
      PlayerProfileSheet(controller: controller, multiplayer: net, userId: net.session!.userId),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tester The Undying'), findsNothing);
    expect(
      find.descendant(of: find.byType(PlayerProfileSheet), matching: find.text('Tester')),
      findsOne,
    );
  });
}
