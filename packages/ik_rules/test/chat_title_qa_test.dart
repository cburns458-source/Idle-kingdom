import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

GameDatabase _database() => assertGameDatabaseShape(contentDatabaseJson());

void main() {
  test('chat title comes from the equipped save slot, never a client title field', () {
    final db = _database();
    final save = createNewSave(db, 1786568400000);
    expect(chatTitleForSave(save, db), 'The Undying');
    expect(chatTitleFromSavePayload(save.toJson(), db), 'The Undying');
    expect(
      chatTitleFromSavePayload(<String, Object?>{...save.toJson(), 'title': 'Sir'}, db),
      'The Undying',
    );
    expect(chatTitleFromSavePayload(null, db), isNull);
    expect(chatTitleFromSavePayload('Sir', db), isNull);

    expect(
      chatTitleFromSavePayload(<String, Object?>{
        ...save.toJson(),
        'title': 'Sir',
        'hasEverDied': true,
      }, db),
      isNull,
    );

    final faith = save.copyWith(
      hasEverDied: true,
      cosmetics: save.cosmetics.copyWith(
        unlocked: <String>[...save.cosmetics.unlocked, 'COS-0013'],
        equipped: <String, String?>{...save.cosmetics.equipped, titleCosmeticSlotId: 'COS-0013'},
      ),
    );
    expect(chatTitleForSave(faith, db), 'Oruvani');
    expect(
      chatTitleFromSavePayload(<String, Object?>{...faith.toJson(), 'title': 'Sir'}, db),
      'Oruvani',
    );
  });
}
