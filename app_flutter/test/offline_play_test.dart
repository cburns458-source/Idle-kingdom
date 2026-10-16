import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/game_controller.dart';
import 'package:idle_kingdoms/src/ui/app_root.dart';
import 'package:idle_kingdoms/src/ui/app_shell.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_net/testing.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  testWidgets('startup with an unreachable server shows retry and never the game', (tester) async {
    var connects = 0;
    final retryHold = Completer<void>();
    addTearDown(() {
      if (!retryHold.isCompleted) retryHold.complete();
    });
    await tester.pumpWidget(
      IdleKingdomsApp(
        database: database,
        storage: MemorySaveStorage(),
        backendConfig: () =>
            const RemoteBackendConfig(url: 'https://example.supabase.co', anonKey: 'anon'),
        connectBackend: (config, storage) async {
          connects += 1;
          throw StateError('Failed to fetch');
        },
        retryDelay: (_) => retryHold.future,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text(bootRetryMessage), findsOne);
    expect(find.text('Sign in to play'), findsNothing);
    expect(find.byType(AppShell), findsNothing);
    expect(connects, greaterThan(0));

    await tester.pump();
    expect(find.text(bootRetryMessage), findsOne);
    expect(find.byType(AppShell), findsNothing);
  });

  testWidgets('a build with no server refuses to start', (tester) async {
    await tester.pumpWidget(
      IdleKingdomsApp(database: database, storage: MemorySaveStorage(), backendConfig: () => null),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text(bootNoServerMessage), findsOne);
    expect(find.text('Sign in to play'), findsNothing);
    expect(find.byType(AppShell), findsNothing);
  });

  testWidgets('a leftover device save is deleted and never pushed', (tester) async {
    final leftover = startedCharacter(database).copyWith(gold: 777);
    final storage = MemorySaveStorage();
    storage.setItem(saveStorageKey, exportSaveText(leftover));
    final transport = FakeTransport()..database = database.launch;
    final service = RemoteMultiplayerService(
      transport: transport,
      storage: storage,
      retryDelay: (_) async {},
    );

    await tester.pumpWidget(
      IdleKingdomsApp(database: database, storage: storage, multiplayerService: service),
    );
    await tester.pump();
    await tester.pump();

    expect(storage.getItem(saveStorageKey), isNull);
    expect(transport.tables[RemoteTables.saves], isEmpty);
    expect(find.text('Sign in to play'), findsOne);
    expect(find.byType(AppShell), findsOne);
  });

  test('commands while disconnected are refused and change nothing', () async {
    final transport = FakeTransport()..database = database.launch;
    final net = buildRemoteMultiplayer(database, transport: transport);
    addTearDown(net.dispose);
    await net.signUp(
      'hero@example.com',
      'Hero',
      'secret',
      startedCharacter(database),
      adopt: (save, {nowMs}) {},
    );
    expect(net.isSignedIn, isTrue, reason: net.notice);

    final seed = startedCharacter(database).copyWith(currentLocationId: 'LOC-0001', gold: 40);
    expect((await seedHostedSave(net.service, transport, seed)).ok, isTrue);

    final game = buildController(database, seed: seed);
    addTearDown(game.dispose);
    wireHostedPlay(game, net);
    await net.resumeAccount(game.save, adopt: game.adoptAccountSave);

    final before = game.save;
    transport.unreachable = true;
    net.markDisconnected();

    game.startActivity('ACT-0021');
    expect(game.save.currentActivityId, before.currentActivityId);
    expect(game.activityError, GameController.needsConnectionReason);

    expect(game.travelTo('LOC-0009', mainMapId), isFalse);
    expect(game.save.currentLocationId, before.currentLocationId);

    game.commit(game.save.copyWith(gold: 1), command: 'shop_confirm');
    expect(game.save.gold, before.gold);

    expect(transport.calls.where((call) => call == 'game:start_activity'), isEmpty);
    expect(transport.calls.where((call) => call == 'game:travel'), isEmpty);
    expect(transport.calls.where((call) => call == 'game:shop_confirm'), isEmpty);
  });

  test('after reconnect the save matches the server and nothing is replayed', () async {
    final transport = FakeTransport()..database = database.launch;
    final net = buildRemoteMultiplayer(
      database,
      transport: transport,
      reconnectDelay: (_) async {},
    );
    addTearDown(net.dispose);

    await net.signUp(
      'hero@example.com',
      'Hero',
      'secret',
      startedCharacter(database),
      adopt: (save, {nowMs}) {},
    );
    final seed = startedCharacter(database).copyWith(currentLocationId: 'LOC-0001', gold: 40);
    expect((await seedHostedSave(net.service, transport, seed)).ok, isTrue);

    final game = buildController(database, seed: seed);
    addTearDown(game.dispose);
    wireHostedPlay(game, net);
    await net.resumeAccount(game.save, adopt: game.adoptAccountSave);
    expect(game.save.gold, 40);

    final server = seed.copyWith(gold: 250);
    expect((await seedHostedSave(net.service, transport, server)).ok, isTrue);
    expect(game.save.gold, 40);

    transport.unreachable = true;
    net.markDisconnected();
    game.startActivity('ACT-0021');
    expect(game.save.currentActivityId, isNot('ACT-0021'));
    expect(game.save.gold, 40);

    transport.unreachable = false;
    expect(await net.retrySync(), isTrue);
    expect(net.disconnected, isFalse);
    expect(game.save.gold, 250);
    expect(game.save.currentActivityId, isNot('ACT-0021'));
    expect(transport.calls.where((call) => call == 'game:start_activity'), isEmpty);
  });

  test('a signed-out user cannot start, travel, or buy', () {
    final game = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0001', gold: 80),
    );
    addTearDown(game.dispose);
    game.hostedPlay = () => false;
    game.submitGameCommand = (command, [args = const <String, Object?>{}]) async => null;

    final before = game.save;
    game.startActivity('ACT-0021');
    expect(game.save.currentActivityId, before.currentActivityId);
    expect(game.activityError, 'Sign in to play.');

    expect(game.travelTo('LOC-0009', mainMapId), isFalse);
    expect(game.save.currentLocationId, before.currentLocationId);

    game.commit(game.save.copyWith(gold: 1), command: 'shop_confirm');
    expect(game.save.gold, before.gold);
  });

  test('leftover is not pushed when an account has no cloud save', () async {
    final leftover = startedCharacter(database).copyWith(gold: 999);
    final storage = MemorySaveStorage();
    storage.setItem(saveStorageKey, exportSaveText(leftover));
    final transport = FakeTransport()..database = database.launch;
    final net = buildRemoteMultiplayer(database, transport: transport);
    addTearDown(net.dispose);
    net.pendingLeftover = leftover;
    net.onAccountSaveReady = () => discardLeftoverDeviceSave(storage);

    await net.signUp('hero@example.com', 'Hero', 'secret', leftover, adopt: (save, {nowMs}) {});

    expect(net.pendingLeftover, isNull);
    expect(storage.getItem(saveStorageKey), isNull);
    expect(transport.tables[RemoteTables.saves], isEmpty);
  });
}
