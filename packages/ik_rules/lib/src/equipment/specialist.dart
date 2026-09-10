import 'package:ik_content/ik_content.dart';

import '../config.dart';
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

String specialistChefHatItemId(GameDatabase db) =>
    configString(db, 'specialist.chef_hat_item_id', chefHatItemId);

String specialistWizardHatItemId(GameDatabase db) =>
    configString(db, 'specialist.wizard_hat_item_id', wizardHatItemId);

String specialistQuiverItemId(GameDatabase db) =>
    configString(db, 'specialist.quiver_item_id', quiverItemId);

String specialistAlchemistGogglesItemId(GameDatabase db) =>
    configString(db, 'specialist.alchemist_goggles_item_id', alchemistGogglesItemId);

bool hasEquippedItem(PlayerSave save, String itemId) {
  return save.equipment.slots.values.any((stack) => stack?.itemId == itemId);
}

/// 1% essence discount, with the remaining cost rounded up.
num wizardEssenceCost(GameDatabase db, num baseQuantity, PlayerSave save) {
  if (baseQuantity <= 0) return 0;
  if (!hasEquippedItem(save, specialistWizardHatItemId(db))) return baseQuantity;
  final factor = configNumber(db, 'specialist.wizard_hat_essence_factor', wizardHatEssenceFactor);
  return (baseQuantity * factor).ceil();
}

num applyQuiverHuntingXp(GameDatabase db, num amount, PlayerSave save, String skillId) {
  if (amount <= 0) return 0;
  if (skillId != huntingSkillId) return amount;
  if (!hasEquippedItem(save, specialistQuiverItemId(db))) return amount;
  final factor = configNumber(db, 'specialist.quiver_hunting_xp_factor', quiverHuntingXpFactor);
  return (amount * factor).floor();
}

num chefHatOutputQuantity(
  GameDatabase db,
  num baseQuantity,
  PlayerSave save,
  String skillId,
  double Function() random,
) {
  if (baseQuantity <= 0) return 0;
  if (skillId != cookingSkillId) return baseQuantity;
  if (!hasEquippedItem(save, specialistChefHatItemId(db))) return baseQuantity;
  final chance = configNumber(db, 'specialist.chef_hat_double_chance', chefHatDoubleChance);
  if (random() >= chance) return baseQuantity;
  return baseQuantity * 2;
}

/// Fair die for potion crafts: 1–3 normally, 2–3 with Alchemist Goggles.
num alchemyPotionOutputQuantity(
  GameDatabase db,
  num baseQuantity,
  PlayerSave save,
  String skillId,
  double Function() random,
) {
  if (baseQuantity <= 0) return 0;
  if (skillId != alchemySkillId) return baseQuantity;
  final roll = random();
  final max = configNumber(db, 'specialist.alchemy_potion_output_max', alchemyPotionOutputMax);
  final min = configNumber(db, 'specialist.alchemy_potion_output_min', alchemyPotionOutputMin);
  final gogglesMin = configNumber(
    db,
    'specialist.alchemy_potion_output_goggles_min',
    alchemyPotionOutputGogglesMin,
  );
  if (hasEquippedItem(save, specialistAlchemistGogglesItemId(db))) {
    final die = (roll * (max - gogglesMin + 1)).floor() + gogglesMin;
    return baseQuantity * die;
  }
  final die = (roll * max).floor() + min;
  return baseQuantity * die;
}

/// Per-craft output used when reserving bag space for a production queue.
num productionOutputReservePerCraft(GameDatabase db, String skillId, num baseQuantity) {
  if (skillId == alchemySkillId) {
    return baseQuantity *
        configNumber(db, 'specialist.alchemy_potion_output_max', alchemyPotionOutputMax);
  }
  return baseQuantity;
}
