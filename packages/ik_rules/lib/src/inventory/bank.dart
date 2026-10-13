import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../save/generated/save_models.dart';
import 'add_items.dart';
import 'capacity.dart';
import 'fit.dart';
import 'gold.dart';

/// Dedicated bank nodes on the Town and Citadel maps (and any future `*_bank`).
const List<String> bankLocationIds = knownBankLocationIds;

bool locationHasBank(LocationRow? location) => locationLooksLikeBank(location);

List<InventoryStack> bankStacks(PlayerSave save) => save.bank;

int bankSlotsFree(PlayerSave save) =>
    inventorySlotsFree(save.copyWith(inventory: save.bank), bankSlotLimit);

/// Gold currency cannot be deposited; enchanted gold stacks still take a slot.
bool stackIsUnbankableGold(InventoryStack stack) =>
    isGoldCurrencyItem(stack.itemId) && isBlank(stack.enchantmentId);

/// Only gold currency is blocked from the chest.
bool stackIsUnbankable(InventoryStack stack) => stackIsUnbankableGold(stack);

bool canFitInBank(
  PlayerSave save,
  String itemId,
  num quantity, [
  String? enchantmentId,
  bool favorite = false,
]) {
  if (stackIsUnbankable(
    InventoryStack(itemId: itemId, quantity: 1, enchantmentId: enchantmentId),
  )) {
    return false;
  }
  return canFitItemQuantity(
    _withBankAsBag(save),
    itemId,
    quantity,
    enchantmentId,
    favorite,
    null,
    bankSlotLimit,
  );
}

PlayerSave _withBankAsBag(PlayerSave save) => save.copyWith(inventory: save.bank);

PlayerSave _restoreBag(PlayerSave original, PlayerSave banked) =>
    banked.copyWith(inventory: original.inventory, bank: banked.inventory);

class BankMoveResult {
  const BankMoveResult.ok(this.save) : reason = null, code = null, noRoom = null;

  const BankMoveResult.failed(this.reason, {this.code, this.noRoom}) : save = null;

  final PlayerSave? save;
  final String? reason;
  final String? code;
  final NoRoom? noRoom;

  bool get ok => reason == null;

  Map<String, Object?> toJson() => ok
      ? <String, Object?>{'ok': true, 'save': save!.toJson()}
      : <String, Object?>{
          'ok': false,
          'reason': reason,
          if (code != null) 'code': code,
          if (noRoom != null) 'noRoom': noRoom!.toJson(),
        };
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

NoRoom _withBankTarget(NoRoom noRoom) {
  if (noRoom.reason == 'stack_full') return const NoRoom(reason: 'stack_full');
  return NoRoom(slotsNeeded: noRoom.slotsNeeded, slotsFree: noRoom.slotsFree, target: 'bank');
}

BankMoveResult _noRoomMove(NoRoom noRoom) =>
    BankMoveResult.failed(noRoomReason(noRoom), code: 'no_room', noRoom: noRoom);

BankMoveResult _moveStack({
  required PlayerSave save,
  required List<InventoryStack> from,
  required bool toBank,
  required int index,
  required num quantity,
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
  if (stackIsUnbankable(piece)) {
    return const BankMoveResult.failed('Gold cannot be deposited.');
  }
  final favorite = piece.favorite == true;
  final slotLimit = toBank ? bankSlotLimit : inventorySlotLimit;
  final target = toBank
      ? _withBankAsBag(save.copyWith(inventory: taken.stacks))
      : save.copyWith(bank: taken.stacks);
  final grant = ItemGrant(
    itemId: piece.itemId,
    quantity: piece.quantity,
    enchantmentId: piece.enchantmentId,
  );
  final blocked = noRoomFor(target, [grant], null, slotLimit);
  if (blocked != null) {
    return _noRoomMove(toBank ? _withBankTarget(blocked) : blocked);
  }
  final added = addItemToInventoryExact(
    toBank ? _withBankAsBag(save.copyWith(inventory: taken.stacks)) : save,
    piece.itemId,
    piece.quantity,
    piece.enchantmentId,
    favorite,
    null,
    slotLimit,
  );
  if (!added.ok) {
    final slotsFree = inventorySlotsFree(target, slotLimit);
    if (slotsFree <= 0) {
      return _noRoomMove(
        toBank
            ? const NoRoom(slotsNeeded: 1, slotsFree: 0, target: 'bank')
            : const NoRoom(slotsNeeded: 1, slotsFree: 0),
      );
    }
    return _noRoomMove(const NoRoom(reason: 'stack_full'));
  }
  if (toBank) {
    return BankMoveResult.ok(_restoreBag(save.copyWith(inventory: taken.stacks), added.save!));
  }
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
  );
}
