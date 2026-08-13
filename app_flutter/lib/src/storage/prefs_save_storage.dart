import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The save slot, backed by `shared_preferences`.
///
/// [SaveStorage] is synchronous on purpose — the rules write a save in the middle
/// of a tick and cannot await — so the stored value is read once at startup and
/// kept in memory, with writes mirrored out to the platform in the background.
/// That is the same shape as `localStorage` in the browser, which is what the
/// React client uses.
class PrefsSaveStorage implements SaveStorage {
  PrefsSaveStorage._(this._prefs, this._cache);

  final SharedPreferencesWithCache _prefs;
  final Map<String, String> _cache;

  static Future<PrefsSaveStorage> open() async {
    final prefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(allowList: <String>{saveStorageKey}),
    );
    final existing = prefs.getString(saveStorageKey);
    final cache = <String, String>{};
    if (existing != null) cache[saveStorageKey] = existing;
    return PrefsSaveStorage._(prefs, cache);
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
