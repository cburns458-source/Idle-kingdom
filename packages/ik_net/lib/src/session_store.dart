import 'dart:convert';

import 'package:ik_runtime/ik_runtime.dart';

import 'types.dart';

/// Where the signed-in session lives between launches.
///
/// The browser build keeps it in `localStorage` under the same key, so a player
/// who signed in on the React client stays signed in on the Flutter one.
class SessionStore {
  const SessionStore(this.storage);

  final SaveStorage storage;

  MultiplayerSession? read() {
    final raw = storage.getItem(multiplayerSessionKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;
      return MultiplayerSession.fromJson(decoded);
    } on Object {
      return null;
    }
  }

  void write(MultiplayerSession? session) {
    if (session == null) {
      storage.removeItem(multiplayerSessionKey);
      return;
    }
    storage.setItem(multiplayerSessionKey, jsonEncode(session.toJson()));
  }

  bool get isSignedIn => read() != null;
}
