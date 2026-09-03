import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ik_bot/ik_bot.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

/// Default live account when `BOT_EMAIL` / `BOT_PASSWORD` are unset.
const String defaultBotEmail = 'bot@email.com';
const String defaultBotPassword = 'password';

const Duration tickEvery = Duration(seconds: 1);
const Duration saveDebounce = Duration(seconds: 8);
const Duration presenceEvery = Duration(seconds: 45);

Future<void> main(List<String> args) async {
  final url = Platform.environment['SUPABASE_URL'];
  final anonKey = Platform.environment['SUPABASE_ANON_KEY'];
  final config = RemoteBackendConfig.from(url: url, anonKey: anonKey);
  if (config == null) {
    stderr.writeln(
      'Live play needs SUPABASE_URL and SUPABASE_ANON_KEY '
      '(the same values as the web client). This host has neither, so the bot '
      'is not signing in. Run locally with those env vars set.',
    );
    exitCode = 2;
    return;
  }

  final email = Platform.environment['BOT_EMAIL'] ?? defaultBotEmail;
  final password = Platform.environment['BOT_PASSWORD'] ?? defaultBotPassword;
  final rng = Random();
  final wanderer = 'Wanderer${rng.nextInt(10000).toString().padLeft(4, '0')}';

  final db = _loadWorkspaceDatabase();
  final storage = MemorySaveStorage();
  final transport = DartSupabaseTransport.connect(config);
  final service = RemoteMultiplayerService(transport: transport, storage: storage);

  stdout.writeln('Signing in as $email …');
  var sessionResult = await service.signIn(email, password);
  if (!sessionResult.ok) {
    stdout.writeln('Sign-in failed (${sessionResult.reason}). Trying sign-up as $wanderer …');
    sessionResult = await service.signUp(email, wanderer, password);
  }
  if (!sessionResult.ok) {
    stderr.writeln('Could not sign in or sign up: ${sessionResult.reason}');
    exitCode = 1;
    return;
  }
  final token = sessionResult.session?.accessToken;
  if (token == null || token.isEmpty) {
    stderr.writeln(
      'Account exists but there is no session. Confirm the email in Supabase '
      'if the project requires it, then run again.',
    );
    exitCode = 1;
    return;
  }

  await service.claimPlaySession();

  final game = GameSession(
    db: db,
    repository: SaveRepository(storage: storage, clock: _wallMs),
    clock: _wallMs,
    random: rng.nextDouble,
  );
  game.boot();

  final pulled = await service.pullSave();
  if (pulled.ok && (pulled.save!.characterName?.trim().isNotEmpty ?? false)) {
    game.adoptAccount(pulled.save!, nowMs: await service.authoritativeNowMs());
    stdout.writeln('Adopted cloud save ${game.save.characterName}.');
  }

  final runner = BotRunner(session: game);
  if (game.save.characterName == null || game.save.raceId == null) {
    runner.ensureHuman(wanderer);
    final claimed = await service.claimAccountUsername(game.save.characterName ?? wanderer);
    if (!claimed.ok) stdout.writeln('Username claim: ${claimed.reason}');
    final published = await service.pushSave(db, game.save, force: true);
    if (!published.ok) {
      stderr.writeln('Could not publish the new character: ${published.reason}');
    } else {
      stdout.writeln('Created ${game.save.characterName} ($botRaceId).');
    }
  } else {
    stdout.writeln('Playing ${game.save.characterName} at ${game.save.currentLocationId}.');
  }

  PlayerSave? pendingSave;
  Timer? saveTimer;
  DateTime lastPresence = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> flushSave() async {
    saveTimer?.cancel();
    saveTimer = null;
    final outgoing = pendingSave;
    pendingSave = null;
    if (outgoing == null) return;
    if (outgoing.characterName == null || outgoing.raceId == null) return;
    final result = await service.pushSave(db, outgoing, force: true);
    if (!result.ok) stderr.writeln('Save flush failed: ${result.reason}');
  }

  void scheduleSave(PlayerSave save) {
    pendingSave = save;
    saveTimer?.cancel();
    saveTimer = Timer(saveDebounce, () {
      unawaited(flushSave());
    });
  }

  Future<void> pulsePresence() async {
    final now = DateTime.now();
    if (now.difference(lastPresence) < presenceEvery) return;
    lastPresence = now;
    final published = await service.publishPresence(presenceFromSave(game.save));
    if (published == null) {
      stderr.writeln('Presence publish skipped (pending username or backend).');
    }
  }

  var running = true;
  final signals = <StreamSubscription<ProcessSignal>>[];
  void stop() {
    running = false;
  }

  signals.add(ProcessSignal.sigint.watch().listen((_) => stop()));
  if (!Platform.isWindows) {
    signals.add(ProcessSignal.sigterm.watch().listen((_) => stop()));
  }

  stdout.writeln('Live gather bot is playing. Ctrl-C to stop.');
  while (running) {
    final intent = runner.step();
    final save = game.save;
    stdout.writeln(
      '${_describe(intent)} @ ${save.currentLocationId} '
      'gold=${save.gold} play=${(save.playTimeMs / 60000).toStringAsFixed(1)}m',
    );
    scheduleSave(save);
    await pulsePresence();
    await Future<void>.delayed(tickEvery);
  }

  await flushSave();
  await service.clearPresence();
  for (final sub in signals) {
    await sub.cancel();
  }
  stdout.writeln('Stopped.');
}

GameDatabase _loadWorkspaceDatabase() {
  var dir = Directory.current.absolute;
  while (true) {
    final file = File('${dir.path}/content/data/game-database.json');
    if (file.existsSync()) {
      return assertGameDatabaseShape(jsonDecode(file.readAsStringSync()));
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'Could not find content/data/game-database.json above ${Directory.current.path}.',
      );
    }
    dir = parent;
  }
}

num _wallMs() => DateTime.now().toUtc().millisecondsSinceEpoch;

String _describe(BotIntent intent) {
  return switch (intent) {
    BotWait(:final reason) => 'wait:$reason',
    BotTravel(:final locationId) => 'travel:$locationId',
    BotStartGather(:final activityId) => 'gather:$activityId',
    BotStartProduction(:final activityId, :final recipeId, :final quantity) =>
      'produce:$activityId/$recipeId x$quantity',
    BotCompleteProject(:final projectId) => 'project:$projectId',
    BotBuy(:final shopId, :final itemId) => 'buy:$shopId/$itemId',
    BotAcceptQuest(:final questId) => 'accept:$questId',
    BotCompleteQuest(:final questId) => 'complete:$questId',
  };
}
