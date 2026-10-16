import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase database;

  setUpAll(() {
    database = assertGameDatabaseShape(contentDatabaseJson());
  });

  test(
    'depositToGuildBank refuses bound and untradeable items, matching TS guild_bank_deposit',
    () {
      expect(guildBankUntradeableRefusal, "That stays with you; it can't be traded.");

      final macheteSave = createNewSave(database, 1).copyWith(
        inventory: const <InventoryStack>[InventoryStack(itemId: 'ITEM-0406', quantity: 1)],
      );
      final machete = depositToGuildBank(
        emptyGuildBank(),
        macheteSave,
        0,
        1,
        () => 'gb-1',
        db: database,
      );
      expect(machete.ok, isFalse);
      expect(machete.reason, guildBankUntradeableRefusal);
      expect(macheteSave.inventory.single.itemId, 'ITEM-0406');

      final pickSave = createNewSave(database, 1).copyWith(
        inventory: const <InventoryStack>[InventoryStack(itemId: 'ITEM-0313', quantity: 1)],
      );
      final pick = depositToGuildBank(emptyGuildBank(), pickSave, 0, 1, () => 'gb-2', db: database);
      expect(pick.ok, isFalse);
      expect(pick.reason, guildBankUntradeableRefusal);

      final cedarSave = createNewSave(database, 1).copyWith(
        inventory: const <InventoryStack>[InventoryStack(itemId: 'ITEM-0015', quantity: 4)],
      );
      final cedar = depositToGuildBank(
        emptyGuildBank(),
        cedarSave,
        0,
        4,
        () => 'gb-3',
        db: database,
      );
      expect(cedar.ok, isTrue);
      expect(cedar.bank!.items.single.itemId, 'ITEM-0015');
      expect(cedar.save!.inventory, isEmpty);
    },
  );
}
