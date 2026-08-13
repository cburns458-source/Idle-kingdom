import 'dart:convert';

import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';
import 'package:test/test.dart';

GameDatabase contentDatabase() => assertGameDatabaseShape(contentDatabaseJson());

void main() {
  const createdAtMs = 1767225600000; // 2026-01-01T00:00:00.000Z
  late GameDatabase db;

  setUp(() => db = contentDatabase());

  test('exported text imports back as the same save', () {
    final save = createNewSave(db, createdAtMs).copyWith(characterName: 'Rowan', gold: 4321);
    final imported = importSaveText(exportSaveText(save), createdAtMs);
    expect(imported.ok, isTrue);
    expect(imported.save!.toJson(), save.toJson());
  });

  test('imports what the React client wrote to browser storage', () {
    // What `localStorage.getItem('idle-kingdoms.demo.save')` returns: the save
    // JSON, with nothing wrapped around it.
    final stored = jsonEncode(createNewSave(db, createdAtMs).toJson());
    final imported = importSaveText(stored, createdAtMs);
    expect(imported.ok, isTrue);
    expect(imported.save!.currentLocationId, createNewSave(db, createdAtMs).currentLocationId);
  });

  test('migrates an older save on the way in', () {
    final old = <String, Object?>{...createNewSave(db, createdAtMs).toJson(), 'saveVersion': 1};
    final imported = importSaveText(jsonEncode(old), createdAtMs);
    expect(imported.ok, isTrue);
    expect(imported.save!.saveVersion, saveVersion);
  });

  test('refuses anything that is not a save', () {
    expect(importSaveText('  ', createdAtMs).reason, saveImportEmpty);
    expect(importSaveText('not json', createdAtMs).reason, saveImportUnreadable);
    expect(importSaveText('[]', createdAtMs).reason, saveImportUnreadable);
    // Valid JSON, and an object, but missing what a save cannot be read without.
    expect(importSaveText('{"saveVersion":1}', createdAtMs).reason, saveImportUnreadable);
  });

  test('names the character it is now playing', () {
    final save = createNewSave(db, createdAtMs);
    expect(saveImportedNotice(save.copyWith(characterName: 'Rowan')), 'Now playing Rowan.');
    expect(saveImportedNotice(save.copyWith(characterName: '  ')), 'Now playing this save.');
    expect(saveImportedNotice(save), 'Now playing this save.');
  });
}
