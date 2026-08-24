import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = assertGameDatabaseShape(contentDatabaseJson());
  });

  test('adds collected items onto an existing favorited stack', () {
    var save = createNewSave(db, 0).copyWith(inventory: const <InventoryStack>[]);
    save = addItemToInventory(save, 'ITEM-0025', 2);
    save = toggleInventoryFavorite(save, 0)!;

    save = addItemToInventory(save, 'ITEM-0025', 3);
    expect(save.inventory, hasLength(1));
    expect(save.inventory.single.itemId, 'ITEM-0025');
    expect(save.inventory.single.quantity, 5);
    expect(isFavoriteStack(save.inventory.single), isTrue);
  });

  test('grows the favorited pile and leaves a leftover unfavorited pile alone', () {
    var save = createNewSave(db, 0).copyWith(
      inventory: const [
        InventoryStack(itemId: 'ITEM-0025', quantity: 4, favorite: true),
        InventoryStack(itemId: 'ITEM-0025', quantity: 2),
      ],
    );

    save = addItemToInventory(save, 'ITEM-0025', 3);
    expect(save.inventory, hasLength(2));
    expect(save.inventory.first.quantity, 7);
    expect(isFavoriteStack(save.inventory.first), isTrue);
    expect(save.inventory.last.quantity, 2);
    expect(isFavoriteStack(save.inventory.last), isFalse);
  });

  test('a full bag still accepts more when a matching pile exists', () {
    final inventory = <InventoryStack>[
      const InventoryStack(itemId: 'ITEM-0025', quantity: 1, favorite: true),
      for (var i = 0; i < inventorySlotLimit - 1; i++)
        InventoryStack(itemId: 'ITEM-fake-$i', quantity: 1),
    ];
    final save = createNewSave(db, 0).copyWith(inventory: inventory);
    expect(inventorySlotsFree(save), 0);
    expect(maxAddableQuantity(save, 'ITEM-0025'), inventoryStackMax - 1);

    final added = addItemsToInventory(save, 'ITEM-0025', 4);
    expect(added.added, 4);
    expect(added.save.inventory.first.quantity, 5);
    expect(isFavoriteStack(added.save.inventory.first), isTrue);
    expect(added.save.inventory, hasLength(inventorySlotLimit));
  });
}
