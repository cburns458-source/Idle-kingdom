import 'dart:convert';

import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';
import 'package:test/test.dart';

/// The real shared content, which is also what the parity recorder reads.
GameDatabase contentDatabase() => assertGameDatabaseShape(contentDatabaseJson());

void main() {
  const createdAtMs = 1767225600000; // 2026-01-01T00:00:00.000Z
  late num now;
  late MemorySaveStorage storage;
  late SaveRepository repository;

  setUp(() {
    now = createdAtMs;
    storage = MemorySaveStorage();
    repository = SaveRepository(storage: storage, clock: () => now);
  });

  test('creates a save on first load and reuses it afterwards', () {
    final db = contentDatabase();
    final first = repository.loadOrCreate(db);
    expect(first.created, isTrue);
    expect(first.save.createdAt, '2026-01-01T00:00:00.000Z');

    now = createdAtMs + 60000;
    final second = repository.loadOrCreate(db);
    expect(second.created, isFalse);
    expect(second.save.createdAt, first.save.createdAt);
    // Every load touches the save, so the write time moves but nothing else does.
    expect(second.save.updatedAt, '2026-01-01T00:01:00.000Z');
    expect(second.save.gold, first.save.gold);
  });

  test('round-trips a save through storage without losing fields', () {
    final db = contentDatabase();
    final created = repository.loadOrCreate(db).save;
    final edited = created.copyWith(
      characterName: 'Keeper',
      gold: 1234,
      inventory: <InventoryStack>[
        const InventoryStack(itemId: 'ITEM-0100', quantity: 1, favorite: true),
      ],
    );
    repository.write(edited);

    final read = repository.read();
    expect(read, isNotNull);
    expect(read!.toJson(), edited.copyWith(updatedAt: read.updatedAt).toJson());
  });

  test('reads nothing when storage is empty and after a clear', () {
    expect(repository.read(), isNull);
    repository.loadOrCreate(contentDatabase());
    expect(repository.read(), isNotNull);
    repository.clear();
    expect(repository.read(), isNull);
  });

  test('migrates an older save on the way in', () {
    final db = contentDatabase();
    final current = createNewSave(db, createdAtMs).toJson();
    storage.setItem(saveStorageKey, jsonEncode(<String, Object?>{...current, 'saveVersion': 9}));

    final read = repository.read();
    expect(read, isNotNull);
    expect(read!.saveVersion, saveVersion);
  });

  test('reports corrupt bytes instead of throwing a decoding error', () {
    storage.setItem(saveStorageKey, '{not json');
    expect(repository.read, throwsA(isA<CorruptSaveException>()));

    storage.setItem(saveStorageKey, jsonEncode(<String, Object?>{'saveVersion': 3}));
    expect(repository.read, throwsA(isA<CorruptSaveException>()));
  });
}
