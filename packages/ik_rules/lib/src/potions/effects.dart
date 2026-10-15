import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../equipment/loadout.dart';
import '../equipment/specialist.dart';
import '../js_compat.dart';
import '../save/generated/save_models.dart';
import '../tags.dart';
import '../vitals/overheal.dart';

const List<String> _scopeTags = <String>[
  'one_combat_encounter',
  'one_action',
  'one_standard_production_action',
];

/// Parses data-defined potion capability tags into a structured effect.
ActivePotionEffect? parsePotionEffect(
  EquipmentRow? equipment,
  String itemId, [
  String? preferredScope,
]) {
  if (equipment == null) return null;
  final tags = capabilityTags(equipment.raw['Capabilities / Effects']);
  if (!tags.contains('potion_slot')) return null;

  final scopes = _scopeTags.where(tags.contains).toList();
  if (scopes.isEmpty) return null;
  if (preferredScope != null && !scopes.contains(preferredScope)) return null;
  final scope = preferredScope != null && scopes.contains(preferredScope)
      ? preferredScope
      : scopes.contains('one_action')
      ? 'one_action'
      : scopes.first;

  num? damageBonusPercent;
  num? enemyMaxHpDamagePercent;
  num? relativeDropChanceBonusPercent;
  num? baseDurationReductionPercent;
  num? instantHealMaxHpPercent;
  num? regenMaxHpPercentPerRound;
  num? damageBonusMin;
  num? damageBonusMax;

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
      continue;
    }
    final instantHeal = RegExp(r'^heals\s+(\d+(?:\.\d+)?)%\s+of\s+max\s+hp\s+on\s+drink$')
        .firstMatch(tag);
    if (instantHeal != null) {
      instantHealMaxHpPercent = jsNumber(instantHeal.group(1));
      continue;
    }
    final regen = RegExp(r'^heals\s+(\d+(?:\.\d+)?)%\s+of\s+max\s+hp\s+per\s+combat\s+round$')
        .firstMatch(tag);
    if (regen != null) {
      regenMaxHpPercentPerRound = jsNumber(regen.group(1));
      continue;
    }
    final flat = RegExp(r'^\+(\d+(?:\.\d+)?)-(\d+(?:\.\d+)?)\s+flat\s+damage$').firstMatch(tag);
    if (flat != null) {
      damageBonusMin = jsNumber(flat.group(1));
      damageBonusMax = jsNumber(flat.group(2));
    }
  }

  return ActivePotionEffect(
    scope: scope,
    itemId: itemId,
    damageBonusPercent: damageBonusPercent,
    enemyMaxHpDamagePercent: enemyMaxHpDamagePercent,
    relativeDropChanceBonusPercent: relativeDropChanceBonusPercent,
    baseDurationReductionPercent: baseDurationReductionPercent,
    instantHealMaxHpPercent: instantHealMaxHpPercent,
    regenMaxHpPercentPerRound: regenMaxHpPercentPerRound,
    damageBonusMin: damageBonusMin,
    damageBonusMax: damageBonusMax,
    actionsRemaining: potionActionDuration,
  );
}

/// Poison applies to current HP; the save key stays `enemyMaxHpDamagePercent`.
num? enemyCurrentHpDamagePercent(ActivePotionEffect? effect) => effect?.enemyMaxHpDamagePercent;

bool isSpeedPotionItem(GameDatabase db, String? itemId) {
  if (itemId == null || itemId.isEmpty) return false;
  final item = db.items.firstWhereOrNull((row) => row.raw['Item ID'] == itemId);
  final key = (item?.raw['Internal Key'] as String? ?? '').toLowerCase();
  final name = (item?.raw['Display Name'] as String? ?? '').toLowerCase();
  return key.contains('speed') || RegExp(r'\bspeed\b').hasMatch(name);
}

/// Speed potions do not apply to Alchemy; Masterwork and others still do.
bool potionAppliesToProductionSkill(GameDatabase db, String? itemId, String skillId) {
  if (skillId != alchemySkillId) return true;
  return !isSpeedPotionItem(db, itemId);
}

/// Actions still covered. Older saves with no count have one action left.
num potionActionsRemaining(ActivePotionEffect? effect) {
  if (effect == null) return 0;
  final left = effect.actionsRemaining;
  if (left != null) return math.max(0, left.floor());
  return 1;
}

/// Stage badge count: a fresh bottle counts the in-progress apply (6→5).
num potionStageRemaining(ActivePotionEffect? effect, PlayerSave save) {
  final left = potionActionsRemaining(effect);
  if (left <= 0) return 0;
  final busy =
      save.currentActivityId != null ||
      (save.combatEnemyId != null && save.combatEnemyId!.isNotEmpty);
  if (busy && left >= potionActionDuration) return left - 1;
  return left;
}

/// Spends one action of the active bottle. Clears the overlay when it runs out.
PlayerSave tickPotionAction(PlayerSave save) {
  final effect = save.activePotionEffect;
  if (effect == null) return save;
  final left = potionActionsRemaining(effect) - 1;
  if (left <= 0) return save.copyWith(activePotionEffect: null);
  return save.copyWith(activePotionEffect: effect.copyWith(actionsRemaining: left));
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
  final existing = save.activePotionEffect;
  if (existing != null && potionActionsRemaining(existing) > 0) {
    if (existing.scope == scope) {
      return PotionConsumption(save: save, consumed: false, effect: existing, potionName: null);
    }
    // Multi-scope bottles (e.g. luck): an already-open bottle covers the other
    // eligible scope without drinking a second dose.
    final openEquipment = db.equipment.firstWhereOrNull(
      (row) => row.raw['Item ID'] == existing.itemId,
    );
    if (parsePotionEffect(openEquipment, existing.itemId, scope) != null) {
      return PotionConsumption(save: save, consumed: false, effect: existing, potionName: null);
    }
  }

  // Pause blocks new bottles only; an already-running effect keeps ticking.
  if (save.settings.potionsPaused) {
    return PotionConsumption(save: save, consumed: false, effect: null, potionName: null);
  }

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
  final effect = parsePotionEffect(equipment, potion.itemId, scope);
  if (effect == null) {
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
num applyPotionDurationMs(
  num baseDurationMs,
  ActivePotionEffect? effect, [
  GameDatabase? db,
  String? skillId,
]) {
  if (db != null &&
      skillId != null &&
      effect != null &&
      !potionAppliesToProductionSkill(db, effect.itemId, skillId)) {
    return math.max(0, baseDurationMs);
  }
  final reduction = effect?.baseDurationReductionPercent;
  if (reduction == null || reduction <= 0) return math.max(0, baseDurationMs);
  final factor = math.max(0.01, 1 - reduction / 100);
  return math.max(0, (baseDurationMs * factor).floor());
}

/// Instant heal: percent of max HP, capped at max HP (same ceiling as food).
num potionInstantHealAmount(num maxHp, ActivePotionEffect? effect) {
  final percent = effect?.instantHealMaxHpPercent;
  if (percent == null || percent <= 0) return 0;
  return math.max(0, (maxHp * (percent / 100)).floor());
}

num applyPotionInstantHeal(num currentHp, num maxHp, ActivePotionEffect? effect) {
  final amount = potionInstantHealAmount(maxHp, effect);
  if (amount <= 0) return currentHp;
  return healTowardCeiling(currentHp, maxHp, amount, 0);
}

/// Per-round heal: percent of max HP, capped at max HP.
num applyPotionRegenHeal(num currentHp, num maxHp, ActivePotionEffect? effect) {
  final percent = effect?.regenMaxHpPercentPerRound;
  if (percent == null || percent <= 0) return currentHp;
  final amount = math.max(0, (maxHp * (percent / 100)).floor());
  if (amount <= 0) return currentHp;
  return healTowardCeiling(currentHp, maxHp, amount, 0);
}

({num min, num max}) potionFlatDamageBonus(ActivePotionEffect? effect) {
  final min = effect?.damageBonusMin;
  final max = effect?.damageBonusMax;
  return (min: min != null && min.isFinite ? min : 0, max: max != null && max.isFinite ? max : 0);
}

/// Flat HP from the old one-shot "deals N% of enemy maximum HP" tag.
num potionEnemyMaxHpDamage(num enemyMaxHp, ActivePotionEffect? effect) {
  final percent = enemyCurrentHpDamagePercent(effect);
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
  final percent = enemyCurrentHpDamagePercent(effect);
  if (percent == null || percent <= 0) return enemyHp;
  final floorHp = potionEnemyHpFloor(enemyMaxHp);
  if (enemyHp <= floorHp) return enemyHp;
  final damage = (enemyHp * (percent / 100)).floor();
  if (damage <= 0) return enemyHp;
  return math.max(floorHp, enemyHp - damage);
}
