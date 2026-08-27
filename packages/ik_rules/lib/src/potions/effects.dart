import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../equipment/loadout.dart';
import '../js_compat.dart';
import '../save/generated/save_models.dart';
import '../tags.dart';

const List<String> _scopeTags = <String>[
  'one_combat_encounter',
  'one_action',
  'one_standard_production_action',
];

/// Parses data-defined potion capability tags into a structured effect.
ActivePotionEffect? parsePotionEffect(EquipmentRow? equipment, String itemId) {
  if (equipment == null) return null;
  final tags = capabilityTags(equipment.raw['Capabilities / Effects']);
  if (!tags.contains('potion_slot')) return null;

  final scope = _scopeTags.firstWhereOrNull(tags.contains);
  if (scope == null) return null;

  num? damageBonusPercent;
  num? enemyMaxHpDamagePercent;
  num? relativeDropChanceBonusPercent;
  num? baseDurationReductionPercent;

  for (final tag in tags) {
    final damage = RegExp(r'^\+(\d+(?:\.\d+)?)%\s*damage$').firstMatch(tag);
    if (damage != null) {
      damageBonusPercent = jsNumber(damage.group(1));
      continue;
    }
    final poison = RegExp(
      r'^deals\s+(\d+(?:\.\d+)?)%\s+of\s+enemy\s+(?:current\s+hp\s+per\s+combat\s+round|maximum\s+hp)$',
    ).firstMatch(tag);
    if (poison != null) {
      enemyMaxHpDamagePercent = jsNumber(poison.group(1));
      continue;
    }
    final drop = RegExp(r'^\+(\d+(?:\.\d+)?)%\s+relative\s+drop\s+chance$').firstMatch(tag);
    if (drop != null) {
      relativeDropChanceBonusPercent = jsNumber(drop.group(1));
      continue;
    }
    final duration = RegExp(r'^-(\d+(?:\.\d+)?)%\s+base\s+duration$').firstMatch(tag);
    if (duration != null) {
      baseDurationReductionPercent = jsNumber(duration.group(1));
    }
  }

  return ActivePotionEffect(
    scope: scope,
    itemId: itemId,
    damageBonusPercent: damageBonusPercent,
    enemyMaxHpDamagePercent: enemyMaxHpDamagePercent,
    relativeDropChanceBonusPercent: relativeDropChanceBonusPercent,
    baseDurationReductionPercent: baseDurationReductionPercent,
  );
}

PlayerSave clearActivePotionEffect(PlayerSave save) {
  if (save.activePotionEffect == null) return save;
  return save.copyWith(activePotionEffect: null);
}

class PotionConsumption {
  const PotionConsumption({
    required this.save,
    required this.consumed,
    required this.effect,
    required this.potionName,
  });

  final PlayerSave save;
  final bool consumed;
  final ActivePotionEffect? effect;
  final String? potionName;
}

/// Consumes one equipped potion when its scope matches the eligible action.
///
/// Future potions work automatically if they use the same capability tag patterns.
PotionConsumption tryConsumePotionForScope(GameDatabase db, PlayerSave save, String scope) {
  final potion = slotStack(save, potionSlotId);
  if (potion == null || potion.quantity <= 0) {
    final cleared = potion != null
        ? save.copyWith(
            equipment: EquipmentLoadout(slots: {...save.equipment.slots, potionSlotId: null}),
          )
        : save;
    return PotionConsumption(save: cleared, consumed: false, effect: null, potionName: null);
  }

  final equipment = db.equipment.firstWhereOrNull((row) => row.raw['Item ID'] == potion.itemId);
  final effect = parsePotionEffect(equipment, potion.itemId);
  if (effect == null || effect.scope != scope) {
    return PotionConsumption(save: save, consumed: false, effect: null, potionName: null);
  }

  final nextQuantity = potion.quantity - 1;
  final displayName = db.items
      .firstWhereOrNull((item) => item.raw['Item ID'] == potion.itemId)
      ?.raw['Display Name'];

  return PotionConsumption(
    save: save.copyWith(
      equipment: EquipmentLoadout(
        slots: {
          ...save.equipment.slots,
          potionSlotId: nextQuantity > 0
              ? EquippedStack(itemId: potion.itemId, quantity: nextQuantity)
              : null,
        },
      ),
      activePotionEffect: effect,
    ),
    consumed: true,
    effect: effect,
    potionName: displayName is String ? displayName : potion.itemId,
  );
}

/// Applies relative drop-chance bonus from an active one_action potion.
num? applyPotionDropChance(num? baseChance, ActivePotionEffect? effect) {
  if (baseChance == null) return null;
  final bonus = effect?.relativeDropChanceBonusPercent;
  if (bonus == null || bonus == 0) return baseChance;
  return math.min(100, baseChance * (1 + bonus / 100));
}

/// Applies base-duration reduction from an active production potion.
num applyPotionDurationMs(num baseDurationMs, ActivePotionEffect? effect) {
  final reduction = effect?.baseDurationReductionPercent;
  if (reduction == null || reduction <= 0) return math.max(0, baseDurationMs);
  final factor = math.max(0.01, 1 - reduction / 100);
  return math.max(0, (baseDurationMs * factor).floor());
}

/// Flat HP from the old one-shot "deals N% of enemy maximum HP" tag.
num potionEnemyMaxHpDamage(num enemyMaxHp, ActivePotionEffect? effect) {
  final percent = effect?.enemyMaxHpDamagePercent;
  if (percent == null || percent <= 0) return 0;
  return math.max(0, (enemyMaxHp * (percent / 100)).floor());
}

/// Lowest HP poison will leave: 10% of max, and never 0 while the enemy has HP.
num potionEnemyHpFloor(num enemyMaxHp) {
  if (enemyMaxHp <= 0) return 0;
  return math.max(1, (enemyMaxHp * 0.1).floor());
}

/// After the player's swing: 10% of current HP, then clamp to the 10% max floor.
num applyPotionEnemyRoundDamage(num enemyHp, num enemyMaxHp, ActivePotionEffect? effect) {
  final percent = effect?.enemyMaxHpDamagePercent;
  if (percent == null || percent <= 0) return enemyHp;
  final floorHp = potionEnemyHpFloor(enemyMaxHp);
  if (enemyHp <= floorHp) return enemyHp;
  final damage = (enemyHp * (percent / 100)).floor();
  if (damage <= 0) return enemyHp;
  return math.max(floorHp, enemyHp - damage);
}
