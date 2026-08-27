import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../achievements/progress.dart';
import '../equipment/loadout.dart';
import '../js_compat.dart';
import '../save/generated/save_models.dart';
import '../spells/spells.dart';
import '../tags.dart';
import 'stats.dart';

/// The outcome of the post-victory auto-eat.
class FoodConsumption {
  const FoodConsumption({
    required this.save,
    required this.consumed,
    required this.healed,
    required this.foodName,
  });

  final PlayerSave save;
  final bool consumed;

  /// Positive heals, negative damages. Zero when nothing was eaten.
  final num healed;
  final String? foodName;
}

/// Eats one equipped food after a win. Healing food only when below max HP;
/// damaging food always, and never drops the player below 1 HP.
FoodConsumption tryConsumeFoodAfterVictory(GameDatabase db, PlayerSave save) {
  final maxHp = playerMaxHp(db, save);
  FoodConsumption unchanged(PlayerSave next) =>
      FoodConsumption(save: next, consumed: false, healed: 0, foodName: null);

  final food = slotStack(save, foodSlotId);
  if (food == null || food.quantity <= 0) {
    return unchanged(
      food == null
          ? save.copyWith(maxHp: maxHp)
          : save.copyWith(
              maxHp: maxHp,
              equipment: EquipmentLoadout(slots: {...save.equipment.slots, foodSlotId: null}),
            ),
    );
  }

  final equipment = db.equipment.firstWhereOrNull((row) => row.raw['Item ID'] == food.itemId);
  final healAmount = jsNumber(equipment?.raw['Healing Amount'] ?? 0);
  if (healAmount == 0) return unchanged(save.copyWith(maxHp: maxHp));
  final damaging = healAmount < 0;
  if (!damaging && save.currentHp >= maxHp) return unchanged(save.copyWith(maxHp: maxHp));

  final nextQuantity = food.quantity - 1;
  final nextHp = damaging
      ? math.max(1, save.currentHp + healAmount)
      : math.min(maxHp, save.currentHp + healAmount);
  final displayName = db.items
      .firstWhereOrNull((item) => item.raw['Item ID'] == food.itemId)
      ?.raw['Display Name'];

  return FoodConsumption(
    save: recordFoodConsumed(
      save.copyWith(
        maxHp: maxHp,
        currentHp: nextHp,
        equipment: EquipmentLoadout(
          slots: {
            ...save.equipment.slots,
            foodSlotId: nextQuantity > 0
                ? EquippedStack(itemId: food.itemId, quantity: nextQuantity)
                : null,
          },
        ),
      ),
      food.itemId,
    ),
    consumed: true,
    healed: nextHp - save.currentHp,
    foodName: displayName is String ? displayName : food.itemId,
  );
}

num _extraFoodFromItem(GameDatabase db, String itemId) {
  final equipment = db.equipment.firstWhereOrNull((row) => row.raw['Item ID'] == itemId);
  var extra = 0.0;
  for (final tag in capabilityTags(equipment?.raw['Capabilities / Effects'])) {
    final match = RegExp(r'^extra_food_per_round:(\d+(?:\.\d+)?)$').firstMatch(tag);
    if (match != null) extra += jsNumber(match.group(1));
  }
  return extra;
}

/// Extra equipped-food eats after an ongoing combat round. One per Gluttony stack.
num extraFoodPerRound(GameDatabase db, PlayerSave save) {
  var extra = 0.0;
  for (final stack in equippedSpellStacks(save)) {
    extra += _extraFoodFromItem(db, stack.itemId);
  }
  return extra;
}

/// Eats equipped food between combat rounds, once per extra_food_per_round stack.
FoodConsumption consumeFoodBetweenRounds(GameDatabase db, PlayerSave save) {
  final extra = extraFoodPerRound(db, save);
  var current = save;
  var consumed = false;
  var healed = 0.0;
  String? foodName;
  for (var i = 0; i < extra; i += 1) {
    final bite = tryConsumeFoodAfterVictory(db, current);
    current = bite.save;
    if (!bite.consumed) break;
    consumed = true;
    healed += bite.healed;
    foodName = bite.foodName;
  }
  return FoodConsumption(save: current, consumed: consumed, healed: healed, foodName: foodName);
}
