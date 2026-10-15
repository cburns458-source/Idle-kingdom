import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

GameDatabase _database() => assertGameDatabaseShape(contentDatabaseJson());

void main() {
  test('chatTitleFromSavePayload matches titleForSave and ignores a client title field', () {
    final db = _database();
    final save = createNewSave(db, 1786568400000);
    expect(chatTitleForSave(save, db), 'The Undying');
    expect(chatTitleFromSavePayload(save.toJson(), db), 'The Undying');
    expect(chatTitleFromSavePayload(null, db), isNull);
    expect(chatTitleFromSavePayload(<String, Object?>{'characterName': 'vari'}, db), 'The Undying');
    expect(
      chatTitleFromSavePayload(<String, Object?>{
        ...save.toJson(),
        'title': 'Sir',
        'hasEverDied': true,
      }, db),
      isNull,
    );

    final faith = save.copyWith(
      cosmetics: save.cosmetics.copyWith(
        unlocked: <String>[...save.cosmetics.unlocked, 'COS-0013'],
        equipped: <String, String?>{...save.cosmetics.equipped, titleCosmeticSlotId: 'COS-0013'},
      ),
    );
    expect(chatTitleForSave(faith, db), 'Oruvani');
    expect(chatTitleFromSavePayload(faith.toJson(), db), 'Oruvani');
    expect(chatTitleFromSavePayload(faith.toJson()), isNull);
  });
}
