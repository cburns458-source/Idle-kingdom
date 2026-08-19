import 'package:flutter_test/flutter_test.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  testWidgets('a new character carries The Undying', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(controller.save.hasEverDied, isFalse);
    expect(find.text('Tester The Undying'), findsWidgets);

    controller.setShowTitleOnHud(false);
    await tester.pump();
    expect(find.text('Tester The Undying'), findsNothing);
    expect(find.text('Tester'), findsWidgets);
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
  });

  test('unequipping The Undying hides it from the name', () {
    final save = startedCharacter(database);
    final unequipped = equipCosmetic(database.launch, save, titleCosmeticSlotId, null);
    expect(unequipped.ok, isTrue);
    expect(titleForSave(unequipped.save!), isNull);
    expect(displayNameForSave(unequipped.save!, 'Adventurer'), 'Tester');
  });
}
