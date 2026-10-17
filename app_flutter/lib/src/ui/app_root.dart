import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

import '../content/database_loader.dart';
import '../net/supabase_transport.dart';
import '../session/activity_icons_pref.dart';
import '../session/bag_overflow_pref.dart';
import '../session/battery_saver_pref.dart';
import '../session/game_controller.dart';
import '../session/local_player_art.dart';
import '../session/hud_level_pref.dart';
import '../session/map_travel_pref.dart';
import '../session/multiplayer_controller.dart';
import '../session/quest_log_sort_pref.dart';
import '../storage/prefs_store.dart';
import '../theme.dart';
import 'app_shell.dart';
import 'delete_account_page.dart';

/// Shown when this binary was built without a hosted backend.
const String bootNoServerMessage = 'This build has no server';

/// Shown while startup cannot reach the hosted backend.
const String bootRetryMessage = "Can't reach server, retrying…";

/// Connects this device to the hosted backend named by [config].
typedef BackendConnect = Future<MultiplayerService> Function(
  RemoteBackendConfig config,
  SaveStorage storage,
);

/// Opens the hosted project and returns the remote service.
Future<MultiplayerService> connectRemoteBackend(
  RemoteBackendConfig config,
  SaveStorage storage,
) async {
  final transport = await SupabaseTransport.connect(config);
  return RemoteMultiplayerService(transport: transport, storage: storage);
}

/// Deletes a leftover device save from an old local build. Never imported.
void discardLeftoverDeviceSave(SaveStorage storage) {
  storage.removeItem(saveStorageKey);
}

class IdleKingdomsApp extends StatelessWidget {
  const IdleKingdomsApp({
    super.key,
    this.multiplayerService,
    this.backendConfig,
    this.connectBackend,
    this.retryDelay,
    this.storage,
    this.database,
    this.clock,
  });

  /// Tests inject a ready service so boot skips the hosted connect.
  final MultiplayerService? multiplayerService;

  /// Tests override the compile-time backend config.
  final RemoteBackendConfig? Function()? backendConfig;

  /// Tests replace [SupabaseTransport.connect].
  final BackendConnect? connectBackend;

  /// Tests replace the startup backoff wait.
  final Future<void> Function(int failedAttempt)? retryDelay;

  /// Tests inject storage so leftover-delete can be asserted.
  final SaveStorage? storage;

  /// Tests inject the shared database so boot does not read the asset bundle.
  final LoadedDatabase? database;

  final num Function()? clock;

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
      home: BootGate(
        multiplayerService: multiplayerService,
        backendConfig: backendConfig,
        connectBackend: connectBackend,
        retryDelay: retryDelay,
        storage: storage,
        database: database,
        clock: clock,
      ),
    );
  }
}

/// Loads the content and the hosted backend, then hands both to the shell.
class BootGate extends StatefulWidget {
  const BootGate({
    super.key,
    this.multiplayerService,
    this.backendConfig,
    this.connectBackend,
    this.retryDelay,
    this.storage,
    this.database,
    this.clock,
  });

  final MultiplayerService? multiplayerService;
  final RemoteBackendConfig? Function()? backendConfig;
  final BackendConnect? connectBackend;
  final Future<void> Function(int failedAttempt)? retryDelay;
  final SaveStorage? storage;
  final LoadedDatabase? database;
  final num Function()? clock;

  @override
  State<BootGate> createState() => _BootGateState();
}

/// The game and its multiplayer half, both ready to use.
class _BootedGame {
  const _BootedGame({required this.game, required this.multiplayer});

  final GameController game;
  final MultiplayerController multiplayer;
}

enum _BootPhase { loading, noServer, retrying, ready }

class _BootGateState extends State<BootGate> {
  _BootPhase _phase = _BootPhase.loading;
  _BootedGame? _booted;
  bool _started = false;
  Completer<void>? _retryHold;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _started = true;
    unawaited(_bootLoop());
  }

  Future<void> _bootLoop() async {
    final database = widget.database ?? await loadBundledDatabase();
    final storage = widget.storage ?? await PrefsStore.open();
    discardLeftoverDeviceSave(storage);

    final injected = widget.multiplayerService;
    if (injected != null) {
      await _finishBoot(database, storage, injected);
      return;
    }

    final config = (widget.backendConfig ?? remoteBackendConfigFromEnvironment)();
    if (config == null) {
      if (mounted) setState(() => _phase = _BootPhase.noServer);
      return;
    }

    var attempt = 0;
    while (mounted) {
      try {
        final connect = widget.connectBackend ?? connectRemoteBackend;
        final service = await connect(config, storage);
        await _finishBoot(database, storage, service);
        return;
      } on Object {
        attempt += 1;
        if (!mounted) return;
        setState(() => _phase = _BootPhase.retrying);
        await _waitRetry(attempt);
      }
    }
  }

  Future<void> _waitRetry(int attempt) {
    final hold = Completer<void>();
    _retryHold = hold;
    final custom = widget.retryDelay;
    if (custom != null) {
      unawaited(
        custom(attempt).then((_) {
          if (!hold.isCompleted) hold.complete();
        }),
      );
    } else {
      final exp = attempt <= 1 ? 0 : attempt - 1;
      final ms = min(15000, 1000 * (1 << min(exp, 4)));
      _retryTimer?.cancel();
      _retryTimer = Timer(Duration(milliseconds: ms), () {
        if (!hold.isCompleted) hold.complete();
      });
    }
    return hold.future.then((_) {
      _retryHold = null;
    });
  }

  Future<void> _finishBoot(
    LoadedDatabase database,
    SaveStorage storage,
    MultiplayerService service,
  ) async {
    num clock() => widget.clock?.call() ?? DateTime.now().millisecondsSinceEpoch;
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
      activityIcons: ActivityIconsPref.load(storage),
      uiChrome: UiChromePref.load(storage),
      batterySaverPref: BatterySaverPref.load(storage),
      questLogSort: QuestLogSortPref.load(storage),
      bagOverflow: BagOverflowPref.load(storage),
    )..adoptBoot(boot);
    _clearOldDemoWorld(service);
    final multiplayer = MultiplayerController(
      database: database,
      service: service,
      storage: storage,
      clock: clock,
    );
    multiplayer.onAccountCleared = game.resetUnsigned;
    multiplayer.onAccountSaveReady = () => discardLeftoverDeviceSave(storage);
    multiplayer.onHostedSave = game.adoptHostedSave;
    multiplayer.currentSave = () => game.save;
    multiplayer.onQuietMessage = game.announce;
    game.hostedPlay = () => multiplayer.isSignedIn;
    game.playDisconnected = () => multiplayer.disconnected;
    var lastDisconnected = multiplayer.disconnected;
    multiplayer.addListener(() {
      if (!_started || lastDisconnected == multiplayer.disconnected) return;
      lastDisconnected = multiplayer.disconnected;
      game.notifyListeners();
    });
    game.submitGameCommand = (command, [args = const <String, Object?>{}]) async {
      final result = await multiplayer.submitGameCommand(command, args);
      if (command.startsWith('mass_')) {
        game.acceptMassSnapshot(result.mass);
      }
      return result.ok ? null : (result.reason ?? 'Try again.');
    };
    game.submitHostedCommand = (command, [args = const <String, Object?>{}]) async {
      final result = await multiplayer.submitGameCommand(command, args);
      return HostedCommandReceipt(
        reason: result.ok ? null : (result.reason ?? 'Try again.'),
        code: result.code,
        noRoom: result.noRoom,
        pointsSpent: result.pointsSpent,
        plazaPoints: result.plazaPoints,
        save: result.save,
      );
    };
    session.hallCompanyActive = () {
      if (!game.session.hasSave || game.save.currentLocationId != guildHallLocationId) {
        return false;
      }
      final me = multiplayer.session?.userId;
      final guildName = multiplayer.guild?.name;
      if (me == null || guildName == null || guildName.isEmpty) return false;
      return multiplayer.presence.any(
        (row) =>
            row.userId != me && row.locationId == guildHallLocationId && row.guildName == guildName,
      );
    };
    repository.onWrite = multiplayer.scheduleAccountSave;
    if (multiplayer.isSignedIn) {
      await multiplayer.resumeAccount(game.save, adopt: game.adoptAccountSave);
    }
    if (!mounted) {
      game.dispose();
      multiplayer.dispose();
      return;
    }
    setState(() {
      _booted = _BootedGame(game: game, multiplayer: multiplayer);
      _phase = _BootPhase.ready;
    });
  }

  /// Sweeps practice-guild rows an older offline build left on this device.
  void _clearOldDemoWorld(MultiplayerService service) {
    if (service is RemoteMultiplayerService) {
      service.local.clearDemoWorld();
    }
  }

  @override
  void dispose() {
    _started = false;
    _retryTimer?.cancel();
    final hold = _retryHold;
    if (hold != null && !hold.isCompleted) hold.complete();
    _booted?.game.dispose();
    _booted?.multiplayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return switch (_phase) {
      _BootPhase.noServer => const _BootMessage(text: bootNoServerMessage),
      _BootPhase.retrying => const _BootMessage(text: bootRetryMessage),
      _BootPhase.ready =>
        isDeleteAccountPath()
            ? DeleteAccountPage(controller: _booted!.game, multiplayer: _booted!.multiplayer)
            : AppShell(controller: _booted!.game, multiplayer: _booted!.multiplayer),
      _BootPhase.loading => DecoratedBox(
        decoration: woodShellDecoration(),
        child: const Center(child: CircularProgressIndicator(color: Palette.parchmentText)),
      ),
    };
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

double _systemRandom() => _random.nextDouble();
final _random = Random();
