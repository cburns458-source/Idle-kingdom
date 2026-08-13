import 'dart:math';

import 'package:flutter/material.dart';
import 'package:ik_runtime/ik_runtime.dart';

import '../content/database_loader.dart';
import '../session/game_controller.dart';
import '../storage/prefs_save_storage.dart';
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

class _BootGateState extends State<_BootGate> {
  late final Future<GameController> _boot = _bootGame();
  GameController? _controller;

  Future<GameController> _bootGame() async {
    final database = await loadBundledDatabase();
    final storage = await PrefsSaveStorage.open();
    num clock() => DateTime.now().millisecondsSinceEpoch;
    final session = GameSession(
      db: database.launch,
      repository: SaveRepository(storage: storage, clock: clock),
      clock: clock,
      random: _systemRandom,
    );
    final boot = session.boot();
    final controller = GameController(database: database, session: session)..adoptBoot(boot);
    _controller = controller;
    return controller;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GameController>(
      future: _boot,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _BootMessage(text: 'Could not start the game.\n${snapshot.error}');
        }
        final controller = snapshot.data;
        if (controller == null) return const _BootMessage(text: 'Loading the realm…');
        return AppShell(controller: controller);
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
