import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../equipment/loadout.dart';
import '../save/generated/save_models.dart';

List<CosmeticSlotRow> cosmeticSlots(GameDatabase db) => db.cosmeticSlots;

CosmeticSlotRow? cosmeticSlotById(GameDatabase db, String slotId) {
  return db.cosmeticSlots.firstWhereOrNull((row) => row.raw['Cosmetic Slot ID'] == slotId);
}

List<CosmeticRow> cosmeticsForSlot(GameDatabase db, String slotId) {
  return db.cosmetics.where((row) => row.raw['Cosmetic Slot ID'] == slotId).toList();
}

CosmeticRow? cosmeticById(GameDatabase db, String cosmeticId) {
  return db.cosmetics.firstWhereOrNull((row) => row.raw['Cosmetic ID'] == cosmeticId);
}

bool isCosmeticUnlocked(PlayerSave save, String cosmeticId) {
  return save.cosmetics.unlocked.contains(cosmeticId);
}

String? equippedCosmeticId(PlayerSave save, String slotId) {
  return save.cosmetics.equipped[slotId];
}

/// The outcome of unlocking a cosmetic, including whether it was the first one
/// ever, which the wardrobe-unlock popup keys off.
class CosmeticGrantResult {
  const CosmeticGrantResult({required this.save, required this.granted, required this.isFirstEver});

  final PlayerSave save;
  final bool granted;
  final bool isFirstEver;
}

/// Unlocks a cosmetic permanently. Owning multiples has no effect, and since
/// cosmetics live in their own always-owned collection rather than the bag,
/// granting one can never fail for lack of space.
CosmeticGrantResult grantCosmetic(PlayerSave save, String cosmeticId) {
  final current = save.cosmetics;
  if (current.unlocked.contains(cosmeticId)) {
    return CosmeticGrantResult(save: save, granted: false, isFirstEver: false);
  }
  return CosmeticGrantResult(
    save: save.copyWith(cosmetics: current.copyWith(unlocked: [...current.unlocked, cosmeticId])),
    granted: true,
    isFirstEver: current.unlocked.isEmpty,
  );
}

/// Equips an owned cosmetic into its slot, or unequips when [cosmeticId] is null.
///
/// Refused when the cosmetic is not unlocked yet or belongs in another slot.
/// Unlike gear, this can never fail for capacity reasons.
EquipResult equipCosmetic(GameDatabase db, PlayerSave save, String slotId, String? cosmeticId) {
  final current = save.cosmetics;
  if (cosmeticId == null) {
    return EquipResult.ok(
      save.copyWith(cosmetics: current.copyWith(equipped: {...current.equipped, slotId: null})),
    );
  }
  final cosmetic = cosmeticById(db, cosmeticId);
  if (cosmetic == null) return const EquipResult.failed('Unknown Cosmetic.');
  if (cosmetic.raw['Cosmetic Slot ID'] != slotId) {
    return const EquipResult.failed('That Cosmetic does not belong in this slot.');
  }
  if (!current.unlocked.contains(cosmeticId)) {
    return const EquipResult.failed('That Cosmetic has not been unlocked yet.');
  }
  return EquipResult.ok(
    save.copyWith(cosmetics: current.copyWith(equipped: {...current.equipped, slotId: cosmeticId})),
  );
}
