import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = assertGameDatabaseShape(contentDatabaseJson());
  });

  test('the first visit to the Kingswoods grants a Sling', () {
    final save = createNewSave(db, 0).copyWith(currentLocationId: kingswoodsLocationId);
    final first = maybeGrantKingswoodsSling(db, save);
    expect(first.granted, isTrue);
    expect(first.save.claimedKingswoodsSling, isTrue);
    expect(first.save.inventory.any((stack) => stack.itemId == slingItemId), isTrue);
    expect(first.message, contains('Sling'));

    final second = maybeGrantKingswoodsSling(db, first.save);
    expect(second.granted, isFalse);
    expect(second.save.inventory.where((stack) => stack.itemId == slingItemId).single.quantity, 1);
  });

  test('a player who already has a Sling is only stamped as claimed', () {
    final save = createNewSave(db, 0).copyWith(
      currentLocationId: kingswoodsLocationId,
      inventory: const <InventoryStack>[InventoryStack(itemId: slingItemId, quantity: 1)],
    );
    final result = maybeGrantKingswoodsSling(db, save);
    expect(result.granted, isFalse);
    expect(result.save.claimedKingswoodsSling, isTrue);
    expect(result.save.inventory.single.quantity, 1);
  });
}
