import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../equipment/loadout.dart';
import '../js_compat.dart';
import '../save/generated/save_models.dart';
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
  final num healed;
  final String? foodName;
}

/// Eats one equipped food after a win, if it would heal anything.
FoodConsumption tryConsumeFoodAfterVictory(GameDatabase db, PlayerSave save) {
  final maxHp = playerMaxHp(db, save);
  FoodConsumption unchanged(PlayerSave next) =>
      FoodConsumption(save: next, consumed: false, healed: 0, foodName: null);

  if (save.currentHp >= maxHp) return unchanged(save.copyWith(maxHp: maxHp));

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
  if (healAmount <= 0) return unchanged(save.copyWith(maxHp: maxHp));

  final nextQuantity = food.quantity - 1;
  final healed = math.min(healAmount, maxHp - save.currentHp);
  final displayName = db.items
      .firstWhereOrNull((item) => item.raw['Item ID'] == food.itemId)
      ?.raw['Display Name'];

  return FoodConsumption(
    save: save.copyWith(
      maxHp: maxHp,
      currentHp: math.min(maxHp, save.currentHp + healed),
      equipment: EquipmentLoadout(
        slots: {
          ...save.equipment.slots,
          foodSlotId: nextQuantity > 0
              ? EquippedStack(itemId: food.itemId, quantity: nextQuantity)
              : null,
        },
      ),
    ),
    consumed: true,
    healed: healed,
    foodName: displayName is String ? displayName : food.itemId,
  );
}
