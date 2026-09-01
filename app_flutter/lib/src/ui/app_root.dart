import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

import '../content/database_loader.dart';
import '../net/supabase_transport.dart';
import '../session/activity_icons_pref.dart';
import '../session/battery_saver_pref.dart';
import '../session/game_controller.dart';
import '../session/local_player_art.dart';
import '../session/hud_level_pref.dart';
import '../session/hud_title_pref.dart';
import '../session/map_travel_pref.dart';
import '../session/multiplayer_controller.dart';
import '../storage/legacy_browser_save.dart';
import '../storage/prefs_store.dart';
import '../storage/save_adoption.dart';
import '../theme.dart';
import 'app_shell.dart';

class IdleKingdomsApp extends StatelessWidget {
  const IdleKingdomsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RestoriaIdle',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      builder: (context, child) {
        return DefaultTextStyle(
          style: Theme.of(context).textTheme.bodyMedium!
              .copyWith(fontFamily: gameFontFamily, fontWeight: FontWeight.w400),
          child: child ?? const SizedBox.shrink(),
        );
      },
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
    // A leftover device file is offered once if the account has no character.
    adoptForeignSave(storage, readLegacyBrowserSave(saveStorageKey), clock());
    final leftover = _namedLeftover(storage, clock());
    // The playable save lives in memory. The account row is the source of truth.
    final repository = SaveRepository(storage: MemorySaveStorage(), clock: clock);
    final session = GameSession(
      db: database.launch,
      repository: repository,
      clock: clock,
      random: _systemRandom,
    );
    final boot = session.boot();
    final game = GameController(
      database: database,
      session: session,
      localArt: LocalPlayerArt.load(storage),
      mapTravel: MapTravelPref.load(storage),
      hudLevel: HudLevelPref.load(storage),
      hudTitle: HudTitlePref.load(storage),
      activityIcons: ActivityIconsPref.load(storage),
      uiChrome: UiChromePref.load(storage),
      batterySaverPref: BatterySaverPref.load(storage),
    )..adoptBoot(boot);
    final backend = await _multiplayerService(storage);
    _ensureDemoWorld(backend.service, database.launch);
    final multiplayer = MultiplayerController(
      database: database,
      service: backend.service,
      storage: storage,
      clock: clock,
      cloudUnavailable: backend.cloudUnavailable,
    );
    multiplayer.pendingLeftover = leftover;
    multiplayer.onAccountCleared = game.resetUnsigned;
    multiplayer.onAccountSaveReady = () => storage.removeItem(saveStorageKey);
    repository.onWrite = multiplayer.scheduleAccountSave;
    if (multiplayer.isSignedIn) {
      await multiplayer.resumeAccount(game.save, adopt: game.adoptAccountSave);
    }
    final booted = _BootedGame(game: game, multiplayer: multiplayer);
    _booted = booted;
    return booted;
  }

  /// The hosted backend when this build was given one, otherwise this device.
  ///
  /// A project that cannot be reached must not stop the game starting, so a
  /// failed connection falls back to local play rather than throwing.
  Future<({MultiplayerService service, bool cloudUnavailable})> _multiplayerService(
    SaveStorage storage,
  ) async {
    final config = remoteBackendConfigFromEnvironment();
    if (config == null) {
      return (service: LocalMultiplayerService(storage: storage), cloudUnavailable: false);
    }
    try {
      final transport = await SupabaseTransport.connect(config);
      return (
        service: RemoteMultiplayerService(transport: transport, storage: storage),
        cloudUnavailable: false,
      );
    } on Object {
      return (service: LocalMultiplayerService(storage: storage), cloudUnavailable: true);
    }
  }

  /// Seeds the practice guild and its three characters, on this device only.
  ///
  /// A build with a real backend gets none of it: those accounts exist so the
  /// social screens have something in them offline, and on a live game they are
  /// strangers nobody can sign in as. A device that played an offline build
  /// before has them in storage already, so a live build sweeps them out.
  void _ensureDemoWorld(MultiplayerService service, GameDatabase db) {
    if (service is LocalMultiplayerService) {
      service.ensureDemoWorld(db);
    } else if (service is RemoteMultiplayerService) {
      service.local.clearDemoWorld();
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
        if (booted == null) {
          return DecoratedBox(
            decoration: woodShellDecoration(),
            child: const Center(child: CircularProgressIndicator(color: Palette.gold)),
          );
        }
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
      decoration: woodShellDecoration(),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

PlayerSave? _namedLeftover(SaveStorage storage, num nowMs) {
  final raw = storage.getItem(saveStorageKey);
  if (raw == null || raw.isEmpty) return null;
  try {
    final save = parseSave(jsonDecode(raw), nowMs);
    final name = save.characterName?.trim() ?? '';
    if (name.isEmpty || save.raceId == null) return null;
    return save;
  } on Object {
    return null;
  }
}

double _systemRandom() => _random.nextDouble();
final _random = Random();
