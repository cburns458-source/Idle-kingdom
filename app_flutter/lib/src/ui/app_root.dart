import 'dart:math';

import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_runtime/ik_runtime.dart';

import '../content/database_loader.dart';
import '../net/supabase_transport.dart';
import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../storage/prefs_store.dart';
import '../theme.dart';
import 'app_shell.dart';

class IdleKingdomsApp extends StatelessWidget {
  const IdleKingdomsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Idle Kingdoms',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const _BootGate(),
    );
  }
}

/// Loads the content and the save, then hands both to the shell.
class _BootGate extends StatefulWidget {
  const _BootGate();

  @override
  State<_BootGate> createState() => _BootGateState();
}

/// The game and its optional multiplayer half, both ready to use.
class _BootedGame {
  const _BootedGame({required this.game, required this.multiplayer});

  final GameController game;
  final MultiplayerController multiplayer;
}

class _BootGateState extends State<_BootGate> {
  late final Future<_BootedGame> _boot = _bootGame();
  _BootedGame? _booted;

  Future<_BootedGame> _bootGame() async {
    final database = await loadBundledDatabase();
    final storage = await PrefsStore.open();
    num clock() => DateTime.now().millisecondsSinceEpoch;
    final session = GameSession(
      db: database.launch,
      repository: SaveRepository(storage: storage, clock: clock),
      clock: clock,
      random: _systemRandom,
    );
    final boot = session.boot();
    final game = GameController(database: database, session: session)..adoptBoot(boot);
    // Multiplayer runs against the same store the save uses, so a signed-in
    // player keeps their account across launches without a network call.
    final multiplayer = MultiplayerController(
      database: database,
      service: await _multiplayerService(storage),
      storage: storage,
      clock: clock,
    );
    if (multiplayer.isSignedIn) {
      await multiplayer.refresh(game.save);
    }
    final booted = _BootedGame(game: game, multiplayer: multiplayer);
    _booted = booted;
    return booted;
  }

  /// The hosted backend when this build was given one, otherwise this device.
  ///
  /// A project that cannot be reached must not stop the game starting, so a
  /// failed connection falls back to local play rather than throwing.
  Future<MultiplayerService> _multiplayerService(SaveStorage storage) async {
    final config = remoteBackendConfigFromEnvironment();
    if (config == null) return LocalMultiplayerService(storage: storage);
    try {
      final transport = await SupabaseTransport.connect(config);
      return RemoteMultiplayerService(transport: transport, storage: storage);
    } on Object {
      return LocalMultiplayerService(storage: storage);
    }
  }

  @override
  void dispose() {
    _booted?.game.dispose();
    _booted?.multiplayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BootedGame>(
      future: _boot,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _BootMessage(text: 'Could not start the game.\n${snapshot.error}');
        }
        final booted = snapshot.data;
        if (booted == null) return const _BootMessage(text: 'Loading the realm…');
        return AppShell(controller: booted.game, multiplayer: booted.multiplayer);
      },
    );
  }
}

class _BootMessage extends StatelessWidget {
  const _BootMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: Palette.shellGradient),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

double _systemRandom() => _random.nextDouble();
final _random = Random();
