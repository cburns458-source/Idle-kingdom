import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../save/generated/save_models.dart';
import 'add_items.dart';
import 'capacity.dart';
import 'gold.dart';

/// Dedicated bank nodes on the Town and Citadel maps.
const List<String> bankLocationIds = <String>['LOC-0034', 'LOC-0035'];

bool locationHasBank(LocationRow? location) {
  if (location == null) return false;
  return bankLocationIds.contains(location.locationId);
}

List<InventoryStack> bankStacks(PlayerSave save) => save.bank;

int bankSlotsFree(PlayerSave save) => inventorySlotsFree(save.copyWith(inventory: save.bank));

/// Gold currency cannot be deposited; enchanted gold stacks still take a slot.
bool stackIsUnbankableGold(InventoryStack stack) =>
    isGoldCurrencyItem(stack.itemId) && isBlank(stack.enchantmentId);

bool canFitInBank(
  PlayerSave save,
  String itemId,
  num quantity, [
  String? enchantmentId,
  bool favorite = false,
]) {
  if (isGoldCurrencyItem(itemId) && isBlank(enchantmentId)) return false;
  return canFitItemQuantity(_withBankAsBag(save), itemId, quantity, enchantmentId, favorite);
}

PlayerSave _withBankAsBag(PlayerSave save) => save.copyWith(inventory: save.bank);

PlayerSave _restoreBag(PlayerSave original, PlayerSave banked) =>
    banked.copyWith(inventory: original.inventory, bank: banked.inventory);

class BankMoveResult {
  const BankMoveResult.ok(this.save) : reason = null;

  const BankMoveResult.failed(this.reason) : save = null;

  final PlayerSave? save;
  final String? reason;

  bool get ok => reason == null;
}

class _Taken {
  const _Taken({required this.stacks, required this.taken});

  final List<InventoryStack> stacks;
  final InventoryStack taken;
}

_Taken? _takeFromStacks(List<InventoryStack> stacks, int index, num takenQty) {
  if (index < 0 || index >= stacks.length) return null;
  final stack = stacks[index];
  final next = [...stacks];
  if (takenQty >= stack.quantity) {
    next.removeAt(index);
  } else {
    next[index] = stack.copyWith(quantity: stack.quantity - takenQty);
  }
  return _Taken(
    stacks: next,
    taken: stack.copyWith(quantity: takenQty),
  );
}

BankMoveResult _moveStack({
  required PlayerSave save,
  required List<InventoryStack> from,
  required bool toBank,
  required int index,
  required num quantity,
  required String fullMessage,
}) {
  if (index < 0 || index >= from.length) {
    return const BankMoveResult.failed('That stack is not there.');
  }
  final want = quantity.floor();
  if (want <= 0) return const BankMoveResult.failed('Choose a quantity.');
  final taken = _takeFromStacks(
    from,
    index,
    want < from[index].quantity ? want : from[index].quantity,
  );
  if (taken == null) return const BankMoveResult.failed('That stack is not there.');
  final piece = taken.taken;
  if (stackIsUnbankableGold(piece)) {
    return const BankMoveResult.failed('Gold cannot be deposited.');
  }
  final favorite = piece.favorite == true;
  final target = toBank
      ? _withBankAsBag(save.copyWith(inventory: taken.stacks))
      : save.copyWith(bank: taken.stacks);
  if (!canFitItemQuantity(target, piece.itemId, piece.quantity, piece.enchantmentId, favorite)) {
    return BankMoveResult.failed(fullMessage);
  }
  if (toBank) {
    final added = addItemToInventoryExact(
      _withBankAsBag(save.copyWith(inventory: taken.stacks)),
      piece.itemId,
      piece.quantity,
      piece.enchantmentId,
      favorite,
    );
    if (!added.ok) return BankMoveResult.failed(added.reason ?? fullMessage);
    return BankMoveResult.ok(_restoreBag(save.copyWith(inventory: taken.stacks), added.save!));
  }
  final added = addItemToInventoryExact(
    save,
    piece.itemId,
    piece.quantity,
    piece.enchantmentId,
    favorite,
  );
  if (!added.ok) return BankMoveResult.failed(added.reason ?? fullMessage);
  return BankMoveResult.ok(added.save!.copyWith(bank: taken.stacks));
}

/// Moves a bag stack into the bank. Gold cannot be deposited.
BankMoveResult depositToBank(PlayerSave save, int inventoryIndex, num quantity) {
  return _moveStack(
    save: save,
    from: save.inventory,
    toBank: true,
    index: inventoryIndex,
    quantity: quantity,
    fullMessage: 'Bank is full ($inventorySlotLimit slots).',
  );
}

/// Moves a bank stack back into the bag.
BankMoveResult withdrawFromBank(PlayerSave save, int bankIndex, num quantity) {
  return _moveStack(
    save: save,
    from: save.bank,
    toBank: false,
    index: bankIndex,
    quantity: quantity,
    fullMessage: 'Inventory is full ($inventorySlotLimit slots).',
  );
}
