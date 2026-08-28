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

/// Extra victory eats. One per Gluttony stack. Does not fire between rounds.
num extraFoodPerRound(GameDatabase db, PlayerSave save) {
  var extra = 0.0;
  for (final stack in equippedSpellStacks(save)) {
    extra += _extraFoodFromItem(db, stack.itemId);
  }
  return extra;
}

/// Victory already eats one food. Each Gluttony stack adds another eat on top.
/// Combat rounds do not eat.
FoodConsumption consumeFoodAfterVictory(GameDatabase db, PlayerSave save) {
  final times = 1 + extraFoodPerRound(db, save);
  var current = save;
  var consumed = false;
  var healed = 0.0;
  String? foodName;
  for (var i = 0; i < times; i += 1) {
    final bite = tryConsumeFoodAfterVictory(db, current);
    current = bite.save;
    if (!bite.consumed) break;
    consumed = true;
    healed += bite.healed;
    foodName = bite.foodName;
  }
  return FoodConsumption(save: current, consumed: consumed, healed: healed, foodName: foodName);
}

num foodHealAmount(GameDatabase db, String itemId) {
  final equipment = db.equipment.firstWhereOrNull((row) => row.raw['Item ID'] == itemId);
  return jsNumber(equipment?.raw['Healing Amount'] ?? 0);
}

bool isEdibleItem(GameDatabase db, String itemId) => foodHealAmount(db, itemId) != 0;

bool isInCombat(PlayerSave save) => save.combatEnemyId != null && save.combatEnemyId!.isNotEmpty;

class EatFoodResult {
  const EatFoodResult.ok({required this.save, required this.healed, required this.foodName})
    : reason = null;

  const EatFoodResult.failed(this.reason) : save = null, healed = 0, foodName = null;

  final PlayerSave? save;
  final num healed;
  final String? foodName;
  final String? reason;

  bool get ok => reason == null;
}

({PlayerSave save, num healed, String foodName}) _applyManualEat(
  GameDatabase db,
  PlayerSave save,
  String itemId,
) {
  final maxHp = playerMaxHp(db, save);
  final healAmount = foodHealAmount(db, itemId);
  final damaging = healAmount < 0;
  final nextHp = damaging
      ? math.max(1, save.currentHp + healAmount)
      : save.currentHp >= maxHp
      ? save.currentHp
      : math.min(maxHp, save.currentHp + healAmount);
  final displayName = db.items
      .firstWhereOrNull((item) => item.raw['Item ID'] == itemId)
      ?.raw['Display Name'];
  return (
    save: recordFoodConsumed(save.copyWith(maxHp: maxHp, currentHp: nextHp), itemId),
    healed: nextHp - save.currentHp,
    foodName: displayName is String ? displayName : itemId,
  );
}

/// One-tap eat from a bag stack. Consumes even at full HP (shows +0).
EatFoodResult eatInventoryFood(GameDatabase db, PlayerSave save, num index) {
  if (isInCombat(save)) {
    return const EatFoodResult.failed('You cannot eat during combat.');
  }
  final i = index.toInt();
  if (i < 0 || i >= save.inventory.length) {
    return const EatFoodResult.failed('Nothing to eat.');
  }
  final stack = save.inventory[i];
  if (stack.quantity <= 0) return const EatFoodResult.failed('Nothing to eat.');
  if (!isEdibleItem(db, stack.itemId)) {
    return const EatFoodResult.failed('That cannot be eaten.');
  }

  final eaten = _applyManualEat(db, save, stack.itemId);
  final nextQuantity = stack.quantity - 1;
  final inventory = <InventoryStack>[
    for (var rowIndex = 0; rowIndex < save.inventory.length; rowIndex++)
      if (rowIndex != i)
        save.inventory[rowIndex]
      else if (nextQuantity > 0)
        stack.copyWith(quantity: nextQuantity),
  ];
  return EatFoodResult.ok(
    save: eaten.save.copyWith(inventory: inventory),
    healed: eaten.healed,
    foodName: eaten.foodName,
  );
}

/// One-tap eat from the equipped food slot. Consumes even at full HP (shows +0).
EatFoodResult eatEquippedFood(GameDatabase db, PlayerSave save) {
  if (isInCombat(save)) {
    return const EatFoodResult.failed('You cannot eat during combat.');
  }
  final food = slotStack(save, foodSlotId);
  if (food == null || food.quantity <= 0) {
    return const EatFoodResult.failed('Nothing to eat.');
  }
  if (!isEdibleItem(db, food.itemId)) {
    return const EatFoodResult.failed('That cannot be eaten.');
  }

  final eaten = _applyManualEat(db, save, food.itemId);
  final nextQuantity = food.quantity - 1;
  return EatFoodResult.ok(
    save: eaten.save.copyWith(
      equipment: EquipmentLoadout(
        slots: {
          ...eaten.save.equipment.slots,
          foodSlotId: nextQuantity > 0 ? food.copyWith(quantity: nextQuantity) : null,
        },
      ),
    ),
    healed: eaten.healed,
    foodName: eaten.foodName,
  );
}
