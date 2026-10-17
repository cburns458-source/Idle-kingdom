import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/game_controller.dart';
import 'package:idle_kingdoms/src/session/multiplayer_controller.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/guild_hall_banner.dart';
import 'package:idle_kingdoms/src/ui/guild_panel.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_net/testing.dart';
import 'package:ik_rules/ik_rules.dart';

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
  Finder onTheSheet(Finder text) =>
      find.descendant(of: find.byKey(const Key('game-popup')), matching: text);

  /// Puts the local save on the server and adopts its answers, as the app does.
  Future<void> hostTheSave(
    MultiplayerController net,
    FakeTransport transport,
    GameController controller,
  ) async {
    final seeded = await seedHostedSave(
      net.service as RemoteMultiplayerService,
      transport,
      controller.save,
    );
    expect(seeded.ok, isTrue, reason: seeded.reason);
    net.onHostedSave = controller.adoptHostedSave;
  }

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
    await tester.tap(find.widgetWithText(GameButton, 'Create for $guildCreateGoldCost gold'));
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
    await hostTheSave(net, transport, controller);
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
    expect(find.byKey(const Key('guild-panel-banner')), findsOne);
    expect(
      tester.widget<GuildHallBanner>(find.byKey(const Key('guild-panel-banner'))).banner.background,
      defaultGuildBanner.background,
    );
  });

  testWidgets('hosted create applies the save when the new guild cannot be read', (tester) async {
    final transport = FakeTransport();
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(gold: guildCreateGoldCost + 5),
    );
    addTearDown(controller.dispose);
    final net = buildRemoteMultiplayer(database, transport: transport);
    addTearDown(net.dispose);
    expect((await net.service.signUp('leader@example.com', 'Leader', 'secret')).ok, isTrue);
    await hostTheSave(net, transport, controller);
    await net.refresh(controller.save);
    transport.missingTables.add(RemoteTables.guildsVisible);

    final reason = await net.createGuild(
      const CreateGuildInput(
        name: 'Iron League',
        tag: 'IRN',
        emblem: GuildEmblem(color: '#3d5a80', symbol: 'shield'),
      ),
      controller.save,
      (_) => fail('hosted create should adopt the server save'),
    );

    expect(reason, isNull);
    expect(net.notice, 'Guild created.');
    expect(controller.save.gold, 5);
    expect(transport.tables[RemoteTables.guilds], hasLength(1));
  });

  testWidgets('hosted create still says created when refresh cannot read the guild', (
    tester,
  ) async {
    final transport = FakeTransport();
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(gold: guildCreateGoldCost + 5),
    );
    addTearDown(controller.dispose);
    final net = buildRemoteMultiplayer(database, transport: transport);
    addTearDown(net.dispose);
    expect((await net.service.signUp('leader@example.com', 'Leader', 'secret')).ok, isTrue);
    await hostTheSave(net, transport, controller);
    await net.refresh(controller.save);
    transport.missingTables.add(RemoteTables.guildsVisible);

    final reason = await net.createGuild(
      const CreateGuildInput(
        name: 'Iron League',
        tag: 'IRN',
        emblem: GuildEmblem(color: '#3d5a80', symbol: 'shield'),
      ),
      controller.save,
      (_) => fail('hosted create should adopt the server save'),
    );

    expect(reason, isNull);
    expect(net.notice, 'Guild created.');
    expect(net.guild, isNull, reason: 'the reread and the refresh both missed the row');
    expect(controller.save.gold, 5);
    expect(reason, isNot(contains('not created')));
  });

  testWidgets('under-13s do not see the guild motto', (tester) async {
    final transport = FakeTransport();
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(gold: guildCreateGoldCost + 5),
    );
    addTearDown(controller.dispose);
    final net = buildRemoteMultiplayer(database, transport: transport);
    addTearDown(net.dispose);
    expect((await net.service.signUp('leader@example.com', 'Leader', 'secret')).ok, isTrue);
    await hostTheSave(net, transport, controller);
    await net.refresh(controller.save);

    await pumpPanel(tester, guildScreen(net, controller));
    await fillAndSubmit(tester, name: 'Iron League', tag: 'irn');

    expect(find.byKey(const Key('guild-motto-edit')), findsOneWidget);
    expect(find.text('Motto'), findsNothing);

    expect((await net.service.setGuildMotto(net.guildId!, 'Keep the watch.')).ok, isTrue);
    await net.refresh(controller.save);
    await tester.pumpAndSettle();

    expect(find.text('Motto'), findsOneWidget);
    expect(find.text('Keep the watch.'), findsOneWidget);
    expect(find.byKey(const Key('guild-motto-edit')), findsNothing);

    transport.setAccountStatus(
      net.session!.userId,
      const AccountSocialStatus(ageAnswered: true, chatAllowed: false),
    );
    await net.refreshAccountStatus();
    await tester.pumpAndSettle();

    expect(find.text('Motto'), findsNothing);
    expect(find.text('Keep the watch.'), findsNothing);
    expect(find.byKey(const Key('guild-motto-edit')), findsNothing);
  });

  testWidgets('an empty motto shows only the edit button to a chatting officer', (tester) async {
    final transport = FakeTransport();
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(gold: guildCreateGoldCost + 5),
    );
    addTearDown(controller.dispose);
    final net = buildRemoteMultiplayer(database, transport: transport);
    addTearDown(net.dispose);
    expect((await net.service.signUp('leader@example.com', 'Leader', 'secret')).ok, isTrue);
    await hostTheSave(net, transport, controller);
    await net.refresh(controller.save);

    await pumpPanel(tester, guildScreen(net, controller));
    await fillAndSubmit(tester, name: 'Iron League', tag: 'irn');

    expect(find.byKey(const Key('guild-motto-edit')), findsOneWidget);
    expect(find.text('Motto'), findsNothing);
    expect(find.text('No motto yet.'), findsNothing);

    final recruitController = buildController(database, seed: startedCharacter(database));
    addTearDown(recruitController.dispose);
    final recruit = buildRemoteMultiplayer(database, transport: FakeTransport.joining(transport));
    addTearDown(recruit.dispose);
    expect((await recruit.service.signUp('recruit@example.com', 'Recruit', 'secret')).ok, isTrue);
    await hostTheSave(recruit, transport, recruitController);
    expect((await recruit.service.applyToGuild(net.guildId!, '')).ok, isTrue);
    await recruit.refresh(recruitController.save);
    await pumpPanel(tester, guildScreen(recruit, recruitController));
    await tester.pumpAndSettle();

    expect(find.text('[IRN] Iron League'), findsOneWidget);
    expect(find.byKey(const Key('guild-motto-edit')), findsNothing);
    expect(find.text('Motto'), findsNothing);
    expect(find.text('No motto yet.'), findsNothing);

    transport.setAccountStatus(
      net.session!.userId,
      const AccountSocialStatus(ageAnswered: true, chatAllowed: false),
    );
    await net.refreshAccountStatus();
    await pumpPanel(tester, guildScreen(net, controller));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('guild-motto-edit')), findsNothing);
    expect(find.text('Motto'), findsNothing);
    expect(find.text('No motto yet.'), findsNothing);
  });

  testWidgets('blank motto and application messages leave no row or placeholder', (tester) async {
    final transport = FakeTransport();
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(gold: guildCreateGoldCost + 5),
    );
    addTearDown(controller.dispose);
    final net = buildRemoteMultiplayer(database, transport: transport);
    addTearDown(net.dispose);
    expect((await net.service.signUp('leader@example.com', 'Leader', 'secret')).ok, isTrue);
    await hostTheSave(net, transport, controller);
    await net.refresh(controller.save);

    await pumpPanel(tester, guildScreen(net, controller));
    await fillAndSubmit(tester, name: 'Iron League', tag: 'irn');

    expect(find.byKey(const Key('guild-motto-edit')), findsOneWidget);
    expect(find.text('Motto'), findsNothing);
    expect(find.text('No motto yet.'), findsNothing);
    expect(find.text('No description.'), findsNothing);

    await tester.tap(find.byKey(const Key('guild-motto-edit')));
    await tester.pumpAndSettle();
    expect(find.text('Guild motto'), findsOneWidget);
    await tester.tap(find.widgetWithText(GameButton, 'Cancel'));
    await tester.pumpAndSettle();

    final outsiderController = buildController(database, seed: startedCharacter(database));
    addTearDown(outsiderController.dispose);
    final outsider = buildRemoteMultiplayer(database, transport: FakeTransport.joining(transport));
    addTearDown(outsider.dispose);
    expect((await outsider.service.signUp('look@example.com', 'Looker', 'secret')).ok, isTrue);
    await outsider.refresh(outsiderController.save);
    await pumpPanel(tester, guildScreen(outsider, outsiderController));
    await tester.pumpAndSettle();

    expect(find.text('[IRN] Iron League'), findsOneWidget);
    expect(find.textContaining('No description.'), findsNothing);
    expect(find.text('Motto'), findsNothing);
    expect(find.byKey(const Key('guild-motto-edit')), findsNothing);
    expect(find.textContaining('Accept applications · 1/$guildMaxMembers'), findsOneWidget);

    expect((await net.service.setGuildJoinPolicy(net.guildId!, guildJoinClosed)).ok, isTrue);
    final hopefulController = buildController(database, seed: startedCharacter(database));
    addTearDown(hopefulController.dispose);
    final hopeful = buildRemoteMultiplayer(database, transport: FakeTransport.joining(transport));
    addTearDown(hopeful.dispose);
    expect((await hopeful.service.signUp('hope@example.com', 'Hopeful', 'secret')).ok, isTrue);
    expect((await hopeful.service.applyToGuild(net.guildId!, '')).ok, isTrue);

    await net.refresh(controller.save);
    await pumpPanel(tester, guildScreen(net, controller));
    await tester.pumpAndSettle();

    expect(find.text('Pending applications'), findsOneWidget);
    expect(find.text('Hopeful'), findsOneWidget);
    expect(find.text('No message.'), findsNothing);
    expect(find.text('Guest request.'), findsNothing);
    expect(find.text('Motto'), findsNothing);
    expect(find.text('No motto yet.'), findsNothing);
    expect(find.byKey(const Key('guild-motto-edit')), findsOneWidget);
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

  testWidgets('the create sheet stays in its card when the keyboard opens', (tester) async {
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

    await pumpPanel(tester, guildScreen(net, controller), size: const Size(390, 844));
    await tester.tap(find.textContaining('Create guild ('));
    await tester.pumpAndSettle();

    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();

    final title = onTheSheet(find.text('Create guild'));
    expect(title, findsOne);
    final popup = tester.getRect(find.byKey(const Key('game-popup')));
    final titleBox = tester.getRect(title);
    expect(titleBox.top, greaterThanOrEqualTo(popup.top));
    expect(titleBox.bottom, lessThanOrEqualTo(popup.bottom));
    expect(onTheSheet(find.widgetWithText(TextField, 'Name')), findsOne);
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

    final button = find.widgetWithText(GameButton, 'Create for $guildCreateGoldCost gold');
    expect(tester.widget<GameButton>(button).onPressed, isNotNull, reason: 'never a dead button');

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
    await hostTheSave(net, transport, controller);
    await net.refresh(controller.save);

    transport.failOnce['invoke:$remoteGameFunction'] =
        'new row violates row-level security policy for table "guilds"';

    await pumpPanel(tester, guildScreen(net, controller));
    await fillAndSubmit(tester, name: 'Iron League', tag: 'irn');

    // The reason is in front of the player rather than at the end of a list
    // behind the sheet, and the name they typed is still there to try again.
    expect(onTheSheet(find.textContaining('row-level security')), findsOne);
    expect(find.widgetWithText(TextField, 'Name'), findsOne);
    expect(controller.save.gold, guildCreateGoldCost, reason: 'a refused guild is not paid for');

    // Trying again with the backend no longer refusing works.
    await tester.tap(find.widgetWithText(GameButton, 'Create for $guildCreateGoldCost gold'));
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

  testWidgets('a dropped fetch is retried and the screen stays quiet', (tester) async {
    final transport = FakeTransport();
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    final net = buildRemoteMultiplayer(database, transport: transport);
    addTearDown(net.dispose);
    expect((await net.service.signUp('leader@example.com', 'Leader', 'secret')).ok, isTrue);

    transport.failNextWith =
        'ClientException: Failed to fetch, uri=https://example.supabase.co/rest/v1/profiles';
    await net.refresh(controller.save);

    expect(net.notice, isNull);
  });

  testWidgets('a fetch that stays dead still says so', (tester) async {
    final transport = FakeTransport();
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    final hold = Completer<void>();
    addTearDown(() {
      if (!hold.isCompleted) hold.complete();
    });
    final net = buildRemoteMultiplayer(
      database,
      transport: transport,
      reconnectDelay: (_) => hold.future,
    );
    addTearDown(net.dispose);
    expect((await net.service.signUp('leader@example.com', 'Leader', 'secret')).ok, isTrue);

    // account_status is the first refresh RPC and swallows failures, so the
    // fetch that stays dead has to miss the later profile read as well.
    transport.failNextRepeats = remoteUnreachableAttempts * 2;
    transport.failNextWith =
        'ClientException: Failed to fetch, uri=https://example.supabase.co/rest/v1/profiles';
    await net.refresh(controller.save);

    expect(net.disconnected, isTrue);
    expect(net.notice, isNull);
  });

  testWidgets('a social screen that cannot read says so', (tester) async {
    final transport = FakeTransport();
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    final net = buildRemoteMultiplayer(database, transport: transport);
    addTearDown(net.dispose);
    expect((await net.service.signUp('leader@example.com', 'Leader', 'secret')).ok, isTrue);

    // A project missing the column this build reads is what a skipped migration
    // looks like from here. Pin it to the board read so account_status does not
    // swallow the refusal.
    transport.failOnce['select:${RemoteTables.leaderboardEntries}'] =
        'column leaderboard_snapshots.value_secondary does not exist';
    await net.refresh(controller.save);

    expect(net.notice, contains('value_secondary'));
  });

  testWidgets('the board lists other players and the signed-in one', (tester) async {
    final transport = FakeTransport();
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    final net = buildRemoteMultiplayer(database, transport: transport);
    addTearDown(net.dispose);
    expect((await net.service.signUp('leader@example.com', 'Leader', 'secret')).ok, isTrue);
    expect((await seedHostedSave(net.service, transport, controller.save)).ok, isTrue);
    await net.service.submitLeaderboard(database.launch, controller.save);

    await transport.upsert(RemoteTables.profiles, <RemoteRow>[
      <String, Object?>{'user_id': 'usr_rival', 'username': 'Rival'},
    ]);
    await transport.upsert(RemoteTables.leaderboard, <RemoteRow>[
      <String, Object?>{'user_id': 'usr_rival', 'board_key': boardTotalLevel, 'value': 99},
    ], onConflict: remoteLeaderboardConflict);

    await net.refresh(controller.save);

    expect(net.notice, isNull);
    expect(net.board.map((entry) => entry.username), contains('Rival'));
    expect(net.board.any((entry) => entry.userId == net.session?.userId), isTrue);
  });

  testWidgets('a half-made founding shows one line and a red Disband button', (tester) async {
    final transport = FakeTransport();
    transport.hostsGuildLifecycleRpcs = false;
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(gold: guildCreateGoldCost + 5),
    );
    addTearDown(controller.dispose);
    final net = buildRemoteMultiplayer(database, transport: transport);
    addTearDown(net.dispose);
    expect((await net.service.signUp('leader@example.com', 'Leader', 'secret')).ok, isTrue);
    await hostTheSave(net, transport, controller);
    await net.refresh(controller.save);

    transport.failOnce['update:${RemoteTables.profiles}'] = 'permission denied';
    transport.failTimes['update:${RemoteTables.profiles}'] = 2;
    transport.failOnce['delete:${RemoteTables.guilds}'] = 'permission denied';
    final leftover = await net.service.createGuild(
      const CreateGuildInput(
        name: 'Iron League',
        tag: 'IRN',
        emblem: GuildEmblem(color: '#3d5a80', symbol: 'shield'),
      ),
      controller.save.gold,
    );
    expect(leftover.ok, isFalse);
    expect(net.foundingHalfMade, isTrue);

    await pumpPanel(tester, guildScreen(net, controller));
    await tester.tap(find.textContaining('Create guild ('));
    await tester.pumpAndSettle();

    expect(onTheSheet(find.text('Guild setup didn\'t finish.')), findsOneWidget);
    expect(onTheSheet(find.textContaining('to try again')), findsNothing);
    expect(onTheSheet(find.text('Create guild')), findsNothing);
    expect(find.widgetWithText(TextField, 'Tag (2–4 letters)'), findsNothing);
    final disband = tester.widget<GameButton>(
      onTheSheet(find.widgetWithText(GameButton, 'Disband')),
    );
    expect(disband.tone, GameButtonTone.danger);

    await tester.tap(onTheSheet(find.widgetWithText(GameButton, 'Disband')));
    await tester.pumpAndSettle();
    expect(transport.tables[RemoteTables.guilds], isEmpty);
    expect(net.foundingHalfMade, isFalse);
  });
}
