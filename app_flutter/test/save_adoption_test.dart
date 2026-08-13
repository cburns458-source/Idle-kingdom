import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/storage/save_adoption.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  test('adopts a save left behind when this device has none', () {
    final storage = MemorySaveStorage();
    final left = startedCharacter(database).copyWith(characterName: 'Rowan');

    expect(adoptForeignSave(storage, exportSaveText(left), testStartMs), isTrue);

    final adopted = SaveRepository(storage: storage, clock: () => testStartMs).read();
    expect(adopted!.characterName, 'Rowan');
  });

  test('leaves the save on this device alone', () {
    final mine = startedCharacter(database).copyWith(characterName: 'Tester');
    final storage = MemorySaveStorage();
    final repository = SaveRepository(storage: storage, clock: () => testStartMs);
    repository.write(mine);

    final other = startedCharacter(database).copyWith(characterName: 'Rowan');
    expect(adoptForeignSave(storage, exportSaveText(other), testStartMs), isFalse);
    expect(repository.read()!.characterName, 'Tester');
  });

  test('ignores nothing to adopt and anything unreadable', () {
    final storage = MemorySaveStorage();
    expect(adoptForeignSave(storage, null, testStartMs), isFalse);
    expect(adoptForeignSave(storage, 'left over from something else', testStartMs), isFalse);
    expect(storage.getItem(saveStorageKey), isNull);
  });
}
