import '../save/generated/save_models.dart';

const String essenceItemId = 'ITEM-0011';
const String chefHatItemId = 'ITEM-0165';
const String wizardHatItemId = 'ITEM-0166';
const String quiverItemId = 'ITEM-0303';
const String cookingSkillId = 'SKL-0007';
const String huntingSkillId = 'SKL-0005';

const double chefHatDoubleChance = 1 / 100;
const double wizardHatEssenceFactor = 0.99;
const double quiverHuntingXpFactor = 1.05;

bool hasEquippedItem(PlayerSave save, String itemId) {
  return save.equipment.slots.values.any((stack) => stack?.itemId == itemId);
}

/// 1% essence discount, with the remaining cost rounded up.
num wizardEssenceCost(num baseQuantity, PlayerSave save) {
  if (baseQuantity <= 0) return 0;
  if (!hasEquippedItem(save, wizardHatItemId)) return baseQuantity;
  return (baseQuantity * wizardHatEssenceFactor).ceil();
}

num applyQuiverHuntingXp(num amount, PlayerSave save, String skillId) {
  if (amount <= 0) return 0;
  if (skillId != huntingSkillId) return amount;
  if (!hasEquippedItem(save, quiverItemId)) return amount;
  return (amount * quiverHuntingXpFactor).floor();
}

num chefHatOutputQuantity(
  num baseQuantity,
  PlayerSave save,
  String skillId,
  double Function() random,
) {
  if (baseQuantity <= 0) return 0;
  if (skillId != cookingSkillId) return baseQuantity;
  if (!hasEquippedItem(save, chefHatItemId)) return baseQuantity;
  if (random() >= chefHatDoubleChance) return baseQuantity;
  return baseQuantity * 2;
}
