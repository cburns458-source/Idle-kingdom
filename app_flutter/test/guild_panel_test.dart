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
  Widget guildScreen(MultiplayerController net, GameController controller) =>
      ListenableBuilder(
        listenable: net,
        builder: (context, _) => GuildPanel(controller: controller, multiplayer: net),
      );

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

  testWidgets('a dead create button says what it is waiting for', (tester) async {
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

    // Nothing typed yet: the button names the first thing missing.
    expect(find.text('Guild name needs at least 3 characters.'), findsOne);

    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Iron League');
    await tester.pump();
    expect(find.text('Guild tag must be 2–4 letters.'), findsOne);

    await tester.enterText(find.widgetWithText(TextField, 'Tag (2–4 letters)'), 'irn');
    await tester.pump();
    expect(find.text('Creating a guild costs $guildCreateGoldCost gold.'), findsOne);
  });

  testWidgets('a backend that refuses the write says so instead of nothing', (tester) async {
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

    expect(net.guild, isNull);
    expect(find.textContaining('row-level security'), findsOne);
    expect(controller.save.gold, guildCreateGoldCost, reason: 'a refused guild is not paid for');
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
}
