import '../save/generated/save_models.dart';

const String essenceItemId = 'ITEM-0011';
const String chefHatItemId = 'ITEM-0165';
const String wizardHatItemId = 'ITEM-0166';
const String quiverItemId = 'ITEM-0303';
const String alchemistGogglesItemId = 'ITEM-0318';
const String cookingSkillId = 'SKL-0007';
const String huntingSkillId = 'SKL-0005';
const String alchemySkillId = 'SKL-0010';

const double chefHatDoubleChance = 1 / 100;
const double wizardHatEssenceFactor = 0.99;
const double quiverHuntingXpFactor = 1.05;

/// Max potions granted per Alchemy craft (queue space assumes this).
const num alchemyPotionOutputMax = 3;

/// Min potions granted per Alchemy craft without Alchemist Goggles.
const num alchemyPotionOutputMin = 1;

/// Min potions granted per Alchemy craft with Alchemist Goggles.
const num alchemyPotionOutputGogglesMin = 2;

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

/// Fair die for potion crafts: 1–3 normally, 2–3 with Alchemist Goggles.
num alchemyPotionOutputQuantity(
  num baseQuantity,
  PlayerSave save,
  String skillId,
  double Function() random,
) {
  if (baseQuantity <= 0) return 0;
  if (skillId != alchemySkillId) return baseQuantity;
  final roll = random();
  if (hasEquippedItem(save, alchemistGogglesItemId)) {
    final die = (roll * 2).floor() + alchemyPotionOutputGogglesMin;
    return baseQuantity * die;
  }
  final die = (roll * alchemyPotionOutputMax).floor() + alchemyPotionOutputMin;
  return baseQuantity * die;
}

/// Per-craft output used when reserving bag space for a production queue.
num productionOutputReservePerCraft(String skillId, num baseQuantity) {
  if (skillId == alchemySkillId) {
    return baseQuantity * alchemyPotionOutputMax;
  }
  return baseQuantity;
}
