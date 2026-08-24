import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/xp.dart';
import '../config.dart';
import '../equipment/loadout.dart';
import '../js_compat.dart';
import '../projects/enchantments.dart';
import '../races/races.dart';
import '../save/generated/save_models.dart';
import '../spells/spells.dart';
import 'stats.dart';

/// One active bonus currently applying to the player.
class CombatBonusLine {
  const CombatBonusLine({required this.kind, required this.name, required this.effect});

  /// `enchantment`, `spell`, `potion`, or `race`.
  final String kind;
  final String name;
  final String effect;
}

/// One labeled input that feeds a combat total.
class CombatStatContribution {
  const CombatStatContribution({required this.label, required this.detail});

  final String label;
  final String detail;
}

/// Combat totals plus the bonuses and per-stat sources that produce them.
///
/// Totals come from the live combat helpers so this cannot drift from the
/// numbers used in a fight. The breakdown lists the inputs those helpers read.
class CombatStatSummary {
  const CombatStatSummary({
    required this.damage,
    this.offhandDamage,
    required this.maxHp,
    required this.damageReduction,
    required this.activeBonuses,
    required this.mainhandBreakdown,
    required this.offhandBreakdown,
    required this.healthBreakdown,
    required this.reductionBreakdown,
  });

  final DamageRange damage;
  final DamageRange? offhandDamage;
  final num maxHp;
  final num damageReduction;
  final List<CombatBonusLine> activeBonuses;
  final List<CombatStatContribution> mainhandBreakdown;
  final List<CombatStatContribution> offhandBreakdown;
  final List<CombatStatContribution> healthBreakdown;
  final List<CombatStatContribution> reductionBreakdown;
}

/// Added-up combat stats, active bonuses, and a source breakdown.
CombatStatSummary playerCombatStatSummary(GameDatabase db, PlayerSave save) {
  return CombatStatSummary(
    damage: playerDamageRange(db, save),
    offhandDamage: playerOffhandDamageRange(db, save),
    maxHp: playerMaxHp(db, save),
    damageReduction: playerDamageReduction(db, save),
    activeBonuses: _activeBonuses(db, save),
    mainhandBreakdown: _mainhandBreakdown(db, save),
    offhandBreakdown: _offhandBreakdown(db, save),
    healthBreakdown: _healthBreakdown(db, save),
    reductionBreakdown: _reductionBreakdown(db, save),
  );
}

String _itemName(GameDatabase db, String itemId) {
  final name = db.items
      .firstWhereOrNull((row) => row.raw['Item ID'] == itemId)
      ?.raw['Display Name'];
  return name is String && name.isNotEmpty ? name : itemId;
}

String _rangeLabel(DamageRange range) {
  return '${jsNumberToString(range.min)}–${jsNumberToString(range.max)}';
}

String _signed(num value) {
  final text = jsNumberToString(value);
  return value > 0 ? '+$text' : text;
}

String _percent(num value) => '${_signed(value)}%';

String _multiplier(num value) => '×${jsNumberToString(value)}';

DamageRange _unarmedBase(GameDatabase db) {
  return DamageRange(
    min: configNumber(db, 'unarmed_min_damage', 10),
    max: configNumber(db, 'unarmed_max_damage', 30),
  );
}

DamageRange? _weaponBase(GameDatabase db, String? itemId) {
  if (isBlank(itemId)) return null;
  final weapon = db.equipment.firstWhereOrNull((entry) => entry.raw['Item ID'] == itemId);
  final weaponMin = weapon?.raw['Min Damage'];
  final weaponMax = weapon?.raw['Max Damage'];
  if (weaponMin is! num || weaponMax is! num) return null;
  return DamageRange(min: weaponMin, max: math.max(weaponMin, weaponMax));
}

List<CombatBonusLine> _activeBonuses(GameDatabase db, PlayerSave save) {
  final bonuses = <CombatBonusLine>[];

  for (final stack in save.equipment.slots.values) {
    if (stack == null || isBlank(stack.enchantmentId)) continue;
    final lines = enchantmentTooltipLines(db, stack.enchantmentId);
    if (lines.isEmpty) continue;
    bonuses.add(
      CombatBonusLine(
        kind: 'enchantment',
        name: lines.first,
        effect: lines.length > 1 ? lines[1] : 'Enchanted',
      ),
    );
  }

  final spellCounts = <String, int>{};
  for (final stack in equippedSpellStacks(save)) {
    spellCounts[stack.itemId] = (spellCounts[stack.itemId] ?? 0) + 1;
  }
  for (final entry in spellCounts.entries) {
    final item = db.items.firstWhereOrNull((row) => row.raw['Item ID'] == entry.key);
    final body = spellTooltipLines(db, item, entry.key)
        .where(
          (line) =>
              !line.startsWith('Always active') &&
              !line.startsWith('Duplicate copies') &&
              !line.startsWith('Does not stack'),
        )
        .toList();
    final effect = body.length >= 2
        ? body[1]
        : body.isEmpty
        ? 'Always active while equipped.'
        : body.first;
    final name = _itemName(db, entry.key);
    bonuses.add(
      CombatBonusLine(
        kind: 'spell',
        name: entry.value > 1 ? '$name ×${jsNumberToString(entry.value)}' : name,
        effect: effect,
      ),
    );
  }

  final potion = save.activePotionEffect;
  if (potion != null) {
    bonuses.add(
      CombatBonusLine(
        kind: 'potion',
        name: _itemName(db, potion.itemId),
        effect: _potionEffect(potion),
      ),
    );
  }

  final raceId = save.raceId;
  if (isNotBlank(raceId)) {
    final raceLines = raceBonusSummaryLines(db, raceId!);
    if (raceLines.isNotEmpty) {
      bonuses.add(
        CombatBonusLine(
          kind: 'race',
          name: raceDisplayName(db, raceId) ?? raceId,
          effect: raceLines.join(', '),
        ),
      );
    }
  }

  return bonuses;
}

String _potionEffect(ActivePotionEffect potion) {
  final parts = <String>[];
  final damage = potion.damageBonusPercent;
  if (damage != null && damage > 0) parts.add('${_percent(damage)} damage');
  final poison = potion.enemyMaxHpDamagePercent;
  if (poison != null && poison > 0) {
    parts.add('deals ${jsNumberToString(poison)}% of enemy maximum HP');
  }
  final drop = potion.relativeDropChanceBonusPercent;
  if (drop != null && drop > 0) parts.add('${_percent(drop)} relative drop chance');
  final duration = potion.baseDurationReductionPercent;
  if (duration != null && duration > 0) {
    parts.add('-${jsNumberToString(duration)}% base duration');
  }
  final scope = switch (potion.scope) {
    'one_combat_encounter' => 'this combat',
    'one_action' => 'this action',
    'one_standard_production_action' => 'this craft',
    _ => potion.scope,
  };
  if (parts.isEmpty) return 'Active $scope';
  return '${parts.join(', ')} ($scope)';
}

List<CombatStatContribution> _damageMultiplierLines(GameDatabase db, PlayerSave save) {
  final lines = <CombatStatContribution>[];

  final enchantBonus = equippedEnchantmentDamageBonus(db, save);
  if (enchantBonus != 0) {
    lines.add(CombatStatContribution(label: 'Enchantments', detail: _signed(enchantBonus)));
  }

  final level = getSkillProgress(save, combatSkillId).level;
  final levelMult = combatLevelBonusMultiplier(save);
  if (levelMult != 1) {
    lines.add(
      CombatStatContribution(
        label: 'Combat Level ${jsNumberToString(level)}',
        detail: _multiplier(levelMult),
      ),
    );
  }

  for (final stack in equippedSpellStacks(save)) {
    final percent = spellDamageRangeBonusPercent(db, stack.itemId);
    if (percent <= 0) continue;
    lines.add(
      CombatStatContribution(label: _itemName(db, stack.itemId), detail: _percent(percent)),
    );
  }

  final potion = save.activePotionEffect;
  final potionBonus = potion?.damageBonusPercent;
  if (potionBonus != null && potionBonus > 0 && potion?.scope == 'one_combat_encounter') {
    lines.add(
      CombatStatContribution(label: _itemName(db, potion!.itemId), detail: _percent(potionBonus)),
    );
  }

  return lines;
}

List<CombatStatContribution> _mainhandBreakdown(GameDatabase db, PlayerSave save) {
  final lines = <CombatStatContribution>[];
  final weaponId = save.equipment.slots[weaponToolSlotId]?.itemId;
  final weapon = _weaponBase(db, weaponId);
  if (weapon != null && isNotBlank(weaponId)) {
    lines.add(CombatStatContribution(label: _itemName(db, weaponId!), detail: _rangeLabel(weapon)));
  } else {
    lines.add(CombatStatContribution(label: 'Unarmed', detail: _rangeLabel(_unarmedBase(db))));
  }
  lines.addAll(_damageMultiplierLines(db, save));
  lines.add(
    CombatStatContribution(label: 'Total', detail: _rangeLabel(playerDamageRange(db, save))),
  );
  return lines;
}

List<CombatStatContribution> _offhandBreakdown(GameDatabase db, PlayerSave save) {
  final offhand = playerOffhandDamageRange(db, save);
  if (offhand == null) return const [];

  final lines = <CombatStatContribution>[];
  final offhandId = save.equipment.slots[offhandSlotId]?.itemId;
  final offhandBase = _weaponBase(db, offhandId);
  if (offhandBase != null && isNotBlank(offhandId)) {
    lines.add(
      CombatStatContribution(label: _itemName(db, offhandId!), detail: _rangeLabel(offhandBase)),
    );
  }
  lines.addAll(_damageMultiplierLines(db, save));
  lines.add(CombatStatContribution(label: 'Total', detail: _rangeLabel(offhand)));
  return lines;
}

List<CombatStatContribution> _healthBreakdown(GameDatabase db, PlayerSave save) {
  final lines = <CombatStatContribution>[];

  for (final stack in save.equipment.slots.values) {
    if (stack == null || isBlank(stack.itemId)) continue;
    final row = db.equipment.firstWhereOrNull((entry) => entry.raw['Item ID'] == stack.itemId);
    final bonus = jsNumber(row?.raw['HP Bonus'] ?? 0);
    if (bonus == 0) continue;
    lines.add(CombatStatContribution(label: _itemName(db, stack.itemId), detail: _signed(bonus)));
  }

  final level = getSkillProgress(save, combatSkillId).level;
  final levelMult = combatLevelBonusMultiplier(save);
  if (levelMult != 1) {
    lines.add(
      CombatStatContribution(
        label: 'Combat Level ${jsNumberToString(level)}',
        detail: _multiplier(levelMult),
      ),
    );
  }

  final raceMult = raceMaxHpMultiplier(db, save);
  if (raceMult != 1 && isNotBlank(save.raceId)) {
    lines.add(
      CombatStatContribution(
        label: raceDisplayName(db, save.raceId) ?? save.raceId!,
        detail: _percent((raceMult - 1) * 100),
      ),
    );
  }

  lines.add(
    CombatStatContribution(label: 'Total', detail: jsNumberToString(playerMaxHp(db, save))),
  );
  return lines;
}

List<CombatStatContribution> _reductionBreakdown(GameDatabase db, PlayerSave save) {
  final lines = <CombatStatContribution>[];
  for (final stack in save.equipment.slots.values) {
    if (stack == null || isBlank(stack.itemId)) continue;
    final row = db.equipment.firstWhereOrNull((entry) => entry.raw['Item ID'] == stack.itemId);
    final reduction = jsNumber(row?.raw['Damage Reduction'] ?? 0);
    if (reduction == 0) continue;
    lines.add(
      CombatStatContribution(
        label: _itemName(db, stack.itemId),
        detail: jsNumberToString(reduction),
      ),
    );
  }
  lines.add(
    CombatStatContribution(
      label: 'Total',
      detail: jsNumberToString(playerDamageReduction(db, save)),
    ),
  );
  return lines;
}
