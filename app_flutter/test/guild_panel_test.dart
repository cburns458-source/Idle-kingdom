import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/game_controller.dart';
import 'package:idle_kingdoms/src/session/multiplayer_controller.dart';
import 'package:idle_kingdoms/src/ui/guild_panel.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_net/testing.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  /// The panel as the social screen mounts it, repainting when the net moves.
  Widget guildScreen(MultiplayerController net, GameController controller) => ListenableBuilder(
    listenable: net,
    builder: (context, _) => GuildPanel(controller: controller, multiplayer: net),
  );

  /// The same text can be on the sheet and on the panel behind it, so an
  /// assertion about what the player is looking at says which one it means.
  Finder onTheSheet(Finder text) => find.descendant(of: find.byType(BottomSheet), matching: text);

  /// Fills the create sheet in and presses its button.
  Future<void> fillAndSubmit(
    WidgetTester tester, {
    required String name,
    required String tag,
  }) async {
    await tester.tap(find.textContaining('Create guild ('));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Tag (2–4 letters)'), tag);
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), name);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create for $guildCreateGoldCost gold'));
    await tester.pumpAndSettle();
  }

  testWidgets('the create button founds a guild on a hosted build', (tester) async {
    final transport = FakeTransport();
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(gold: guildCreateGoldCost + 5),
    );
    addTearDown(controller.dispose);
    final net = buildRemoteMultiplayer(database, transport: transport);
    addTearDown(net.dispose);
    final signed = await net.service.signUp('leader@example.com', 'Leader', 'secret');
    expect(signed.ok, isTrue, reason: signed.reason);
    await net.refresh(controller.save);

    await pumpPanel(tester, guildScreen(net, controller));
    await fillAndSubmit(tester, name: 'Iron League', tag: 'irn');

    expect(net.notice, 'Guild created.');
    expect(net.guild?.name, 'Iron League');
    expect(net.guild?.tag, 'IRN');
    // It is a row on the server, not a note on this device.
    expect(transport.tables[RemoteTables.guilds], hasLength(1));
    expect(transport.tables[RemoteTables.guildMembers]!.single['role'], guildRoleLeader);
    expect(controller.save.gold, 5, reason: 'the founding fee is taken once');
    expect(find.text('[IRN] Iron League'), findsOne);
  });

  testWidgets('the create sheet says what it is still waiting for', (tester) async {
    final transport = FakeTransport();
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(gold: 0),
    );
    addTearDown(controller.dispose);
    final net = buildRemoteMultiplayer(database, transport: transport);
    addTearDown(net.dispose);
    expect((await net.service.signUp('broke@example.com', 'Broke', 'secret')).ok, isTrue);
    await net.refresh(controller.save);

    await pumpPanel(tester, guildScreen(net, controller));
    await tester.tap(find.textContaining('Create guild ('));
    await tester.pumpAndSettle();

    // Nothing typed yet: the sheet names the first thing missing.
    expect(find.text('Guild name needs at least 3 characters.'), findsOne);

    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Iron League');
    await tester.pump();
    expect(find.text('Guild tag must be 2–4 letters.'), findsOne);

    await tester.enterText(find.widgetWithText(TextField, 'Tag (2–4 letters)'), 'irn');
    await tester.pump();
    expect(find.text('Creating a guild costs $guildCreateGoldCost gold.'), findsOne);
  });

  testWidgets('the create button presses even when the form is not ready', (tester) async {
    final transport = FakeTransport();
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(gold: 0),
    );
    addTearDown(controller.dispose);
    final net = buildRemoteMultiplayer(database, transport: transport);
    addTearDown(net.dispose);
    expect((await net.service.signUp('broke@example.com', 'Broke', 'secret')).ok, isTrue);
    await net.refresh(controller.save);

    await pumpPanel(tester, guildScreen(net, controller));
    await tester.tap(find.textContaining('Create guild ('));
    await tester.pumpAndSettle();

    final button = find.widgetWithText(FilledButton, 'Create for $guildCreateGoldCost gold');
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull, reason: 'never a dead button');

    await tester.tap(button);
    await tester.pumpAndSettle();

    // Pressed with nothing filled in: the reason is on the sheet, and the sheet
    // is still there with the emblem the player picked.
    expect(onTheSheet(find.text('Guild name needs at least 3 characters.')), findsOne);
    expect(find.widgetWithText(TextField, 'Name'), findsOne);
    expect(net.guild, isNull);
  });

  testWidgets('a refused create keeps the sheet open with the reason on it', (tester) async {
    final transport = FakeTransport();
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(gold: guildCreateGoldCost),
    );
    addTearDown(controller.dispose);
    final net = buildRemoteMultiplayer(database, transport: transport);
    addTearDown(net.dispose);
    expect((await net.service.signUp('leader@example.com', 'Leader', 'secret')).ok, isTrue);
    await net.refresh(controller.save);

    transport.failOnce['insert:${RemoteTables.guilds}'] =
        'new row violates row-level security policy for table "guilds"';

    await pumpPanel(tester, guildScreen(net, controller));
    await fillAndSubmit(tester, name: 'Iron League', tag: 'irn');

    // The reason is in front of the player rather than at the end of a list
    // behind the sheet, and the name they typed is still there to try again.
    expect(onTheSheet(find.textContaining('row-level security')), findsOne);
    expect(find.widgetWithText(TextField, 'Name'), findsOne);
    expect(controller.save.gold, guildCreateGoldCost, reason: 'a refused guild is not paid for');

    // Trying again with the backend no longer refusing works.
    await tester.tap(find.widgetWithText(FilledButton, 'Create for $guildCreateGoldCost gold'));
    await tester.pumpAndSettle();

    expect(net.guild?.name, 'Iron League');
    expect(find.widgetWithText(TextField, 'Name'), findsNothing, reason: 'the sheet closed');
  });

  testWidgets('an action that throws is reported, not swallowed', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    final net = buildMultiplayer(database);
    addTearDown(net.dispose);

    await net.run(() async => throw StateError('the wire went dead'));

    expect(net.notice, contains('the wire went dead'));
    expect(net.busy, isFalse, reason: 'a thrown action still lets go of the buttons');
  });

  testWidgets('a social screen that cannot read says so', (tester) async {
    final transport = FakeTransport();
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    final net = buildRemoteMultiplayer(database, transport: transport);
    addTearDown(net.dispose);
    expect((await net.service.signUp('leader@example.com', 'Leader', 'secret')).ok, isTrue);

    // A project missing the column this build reads is what a skipped migration
    // looks like from here.
    transport.failNextWith = 'column leaderboard_snapshots.value_secondary does not exist';
    await net.refresh(controller.save);

    expect(net.notice, contains('value_secondary'));
  });

  testWidgets('a missing leaderboard embed does not cover Guilds and Chat', (tester) async {
    final transport = FakeTransport();
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    final net = buildRemoteMultiplayer(database, transport: transport);
    addTearDown(net.dispose);
    expect((await net.service.signUp('leader@example.com', 'Leader', 'secret')).ok, isTrue);

    transport.failOnce['select:${RemoteTables.leaderboard}'] = "Could not find a relationship between 'leaderboard_snapshots' and 'profiles' in the schema cache";
    await net.refresh(controller.save);

    expect(net.notice, isNull);
  });
}
