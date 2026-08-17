import 'dart:convert';

import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

/// Key-value storage for the local save, implemented per platform.
///
/// The same shape as the browser's `localStorage`, which is what the React
/// client used; under Flutter it is backed by `shared_preferences`, which the
/// runtime may not import directly.
abstract interface class SaveStorage {
  String? getItem(String key);

  void setItem(String key, String value);

  void removeItem(String key);
}

/// A storage that keeps everything in a map, for tests and for a first run
/// before a platform storage is wired up.
class MemorySaveStorage implements SaveStorage {
  MemorySaveStorage([Map<String, String>? initial]) : _entries = <String, String>{...?initial};

  final Map<String, String> _entries;

  @override
  String? getItem(String key) => _entries[key];

  @override
  void setItem(String key, String value) => _entries[key] = value;

  @override
  void removeItem(String key) => _entries.remove(key);
}

/// Thrown when the stored save exists but cannot be read.
class CorruptSaveException implements Exception {
  CorruptSaveException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Whether the save that came back was freshly created.
class LoadOrCreateResult {
  const LoadOrCreateResult({required this.save, required this.created});

  final PlayerSave save;
  final bool created;
}

/// Reads and writes the single local save, migrating it on the way in.
///
/// Time is a constructor dependency rather than an ambient call so a test can
/// pin it, the same way the ported rules take `nowMs`.
class SaveRepository {
  SaveRepository({required this.storage, required this.clock});

  final SaveStorage storage;

  /// Wall clock in milliseconds; a test pins it instead of reading the host.
  final num Function() clock;

  /// Called after each write, so a signed-in client can mirror the account row.
  void Function(PlayerSave save)? onWrite;

  PlayerSave write(PlayerSave save) {
    final next = touchSave(save, clock());
    storage.setItem(saveStorageKey, jsonEncode(next.toJson()));
    onWrite?.call(next);
    return next;
  }

  PlayerSave? read() {
    final raw = storage.getItem(saveStorageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return parseSave(jsonDecode(raw), clock());
    } on Exception catch (error) {
      throw CorruptSaveException('Corrupt local save: $error');
    }
  }

  LoadOrCreateResult loadOrCreate(GameDatabase db) {
    final existing = read();
    if (existing != null) {
      return LoadOrCreateResult(save: write(existing), created: false);
    }
    return LoadOrCreateResult(save: write(createNewSave(db, clock())), created: true);
  }

  void clear() => storage.removeItem(saveStorageKey);
}
