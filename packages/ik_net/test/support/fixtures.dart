import 'dart:convert';

import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

/// The database a fixture was recorded against.
GameDatabase databaseOf(ParityFixture fixture) =>
    assertGameDatabaseShape(fixtureDatabaseJson(fixture));

/// A save carried in the fixture input under [key].
PlayerSave saveOf(ParityFixture fixture, [String key = 'save']) =>
    PlayerSave.fromJson(asJsonMap(fixture.inputMap[key]));

/// A backend with its clock and ids pinned, mirroring the recorder's harness.
///
/// Ids count up from one so a replay names the same rows the fixture did, and
/// the clock only moves when a scenario asks it to.
class BackendHarness {
  BackendHarness({num startMs = defaultNowMs, String? seed}) : _clock = startMs {
    if (seed != null) storage.setItem(multiplayerLocalDbKey, seed);
    backend = LocalMultiplayerBackend(
      storage: storage,
      ports: LocalBackendPorts(nowMs: () => _clock, newId: _nextId),
    );
  }

  /// The instant every multiplayer fixture was recorded at.
  static const num defaultNowMs = 1786568400000;

  final MemorySaveStorage storage = MemorySaveStorage();
  late final LocalMultiplayerBackend backend;

  num _clock;
  int _counter = 0;

  String _nextId(String prefix) => '${prefix}_${(_counter += 1).toString().padLeft(4, '0')}';

  void advance(num ms) => _clock += ms;

  /// The stored document, as the next load would read it.
  Object? doc() {
    final raw = storage.getItem(multiplayerLocalDbKey);
    return raw == null ? null : jsonDecode(raw);
  }

  MultiplayerSession signUp(String email, String username) {
    final result = backend.signUp(email, username, 'secret');
    if (!result.ok) throw StateError('Fixture sign-up failed: ${result.reason}');
    return result.session!;
  }
}
