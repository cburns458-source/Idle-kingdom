import 'package:ik_runtime/ik_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The device's key-value store, backed by `shared_preferences`.
///
/// [SaveStorage] is synchronous on purpose — the rules write a save in the middle
/// of a tick and cannot await — so every stored string is read once at startup
/// and kept in memory, with writes mirrored out to the platform in the
/// background. That is the same shape as `localStorage` in the browser, which is
/// what the React client used, and the multiplayer backend needs it too: its
/// document, the session, and one read cursor per account all live here.
class PrefsStore implements SaveStorage {
  PrefsStore._(this._prefs, this._cache);

  final SharedPreferencesAsync _prefs;
  final Map<String, String> _cache;

  static Future<PrefsStore> open() async {
    final prefs = SharedPreferencesAsync();
    final cache = <String, String>{};
    // Read everything rather than an allow list: the DM read cursors are named
    // after user ids, which are not known until an account signs in.
    for (final entry in (await prefs.getAll()).entries) {
      final value = entry.value;
      if (value is String) cache[entry.key] = value;
    }
    return PrefsStore._(prefs, cache);
  }

  @override
  String? getItem(String key) => _cache[key];

  @override
  void setItem(String key, String value) {
    _cache[key] = value;
    _prefs.setString(key, value).ignore();
  }

  @override
  void removeItem(String key) {
    _cache.remove(key);
    _prefs.remove(key).ignore();
  }
}
