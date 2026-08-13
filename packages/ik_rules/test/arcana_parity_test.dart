import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// Rebuilds the target an `enchantments/apply` fixture recorded.
EnchantTarget _targetOf(ParityFixture fixture) {
  final target = asJsonMap(fixture.inputMap['target']);
  if (target['kind'] == 'equipped') {
    return EquippedEnchantTarget(target['slotId']! as String);
  }
  return InventoryEnchantTarget((target['index']! as num).toInt());
}

void main() {
  group('spell slot parity', () {
    for (final fixture in loadParityFixtures('spells/slots')) {
      test(fixture.name, () {
        expect(
          checkParity(fixture, {
            'slotIds': spellSlotIds,
            'recognized': spellSlotIds.map(isSpellSlotId).toList(),
            'rejected': isSpellSlotId('SLOT-0001'),
          }),
          isNull,
        );
      });
    }
  });

  group('spell detection parity', () {
    for (final fixture in loadParityFixtures('spells/detection')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        expect(
          checkParity(fixture, {
            'equipment': db.equipment
                .map(
                  (row) => <String, Object?>{
                    'itemId': row.itemId,
                    'spellEquipment': isSpellEquipment(row),
                  },
                )
                .toList(),
            'items': db.items
                .map(
                  (row) => <String, Object?>{
                    'itemId': row.itemId,
                    'spellItem': isSpellItem(db, row.itemId),
                    'effectEnchantmentId': spellEffectEnchantmentId(db, row.itemId),
                    'damageRangeBonus': spellDamageRangeBonusPercent(db, row.itemId),
                    'itemDoubleChance': spellItemDoubleChancePercent(db, row.itemId),
                  },
                )
                .toList(),
          }),
          isNull,
        );
      });
    }
  });

  group('spell tooltip parity', () {
    for (final fixture in loadParityFixtures('spells/tooltips')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final lines = db.items
            .where((row) => isSpellItem(db, row.itemId))
            .map(
              (row) => <String, Object?>{
                'itemId': row.itemId,
                'lines': spellTooltipLines(db, row, row.itemId),
              },
            )
            .toList();
        expect(checkParity(fixture, {'lines': lines}), isNull);
      });
    }
  });

  group('equipped spell parity', () {
    for (final fixture in loadParityFixtures('spells/equipped')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        expect(
          checkParity(fixture, {
            'stacks': equippedSpellStacks(save).map((stack) => stack.toJson()).toList(),
            'firstEmpty': firstEmptySpellSlot(save),
            'damageMultiplier': activeSpellDamageRangeMultiplier(db, save),
            'doubleChance': activeSpellItemDoubleChancePercent(db, save),
          }),
          isNull,
        );
      });
    }
  });

  group('spell bonus combination parity', () {
    for (final fixture in loadParityFixtures('spells/combine')) {
      test(fixture.name, () {
        final contributions = fixture
            .inputField<List<Object?>>('contributions')
            .map(asJsonMap)
            .map(
              (entry) => SpellContribution(
                percent: entry['percent']! as num,
                stacks: entry['stacks']! as bool,
              ),
            )
            .toList();
        expect(
          checkParity(fixture, {
            'combined': combineSpellPercentBonuses(contributions),
            'empty': combineSpellPercentBonuses(const <SpellContribution>[]),
          }),
          isNull,
        );
      });
    }
  });

  group('axe detection parity', () {
    for (final fixture in loadParityFixtures('enchantments/axe-detection')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final rows = db.equipment
            .map(
              (equipment) => <String, Object?>{
                'itemId': equipment.itemId,
                'axe': isAxeItem(
                  db.items.where((item) => item.itemId == equipment.itemId).firstOrNull,
                  equipment,
                ),
              },
            )
            .toList();
        expect(checkParity(fixture, {'rows': rows}), isNull);
      });
    }
  });

  group('enchant target codec parity', () {
    for (final fixture in loadParityFixtures('enchantments/targets')) {
      test(fixture.name, () {
        final decoded = fixture.inputField<List<Object?>>('codes').map((value) {
          final code = value as String;
          final target = decodeEnchantTarget(code);
          return <String, Object?>{
            'code': code,
            'target': switch (target) {
              null => null,
              EquippedEnchantTarget(:final slotId) => <String, Object?>{
                'kind': 'equipped',
                'slotId': slotId,
              },
              InventoryEnchantTarget(:final index) => <String, Object?>{
                'kind': 'inventory',
                'index': index,
              },
            },
            'reencoded': target == null ? null : encodeEnchantTarget(target),
          };
        }).toList();
        expect(checkParity(fixture, {'decoded': decoded}), isNull);
      });
    }
  });

  group('eligible enchantment target parity', () {
    for (final fixture in loadParityFixtures('enchantments/eligible')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        final byEnchantment = db.enchantments
            .map(
              (enchantment) => <String, Object?>{
                'enchantmentId': enchantment.enchantmentId,
                'options': eligibleEnchantmentTargets(
                  db,
                  save,
                  enchantment,
                ).map((option) => option.toJson()).toList(),
              },
            )
            .toList();
        expect(checkParity(fixture, {'byEnchantment': byEnchantment}), isNull);
      });
    }
  });

  group('apply enchantment parity', () {
    for (final fixture in loadParityFixtures('enchantments/apply')) {
      test(fixture.name, () {
        final applied = applyEnchantmentToTarget(saveOf(fixture), _targetOf(fixture), 'ENCH-0003');
        expect(checkParity(fixture, {'save': applied?.toJson()}), isNull);
      });
    }
  });

  group('enchantment bonus parity', () {
    for (final fixture in loadParityFixtures('enchantments/bonuses')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        expect(
          checkParity(fixture, {
            'damageBonus': equippedEnchantmentDamageBonus(db, save),
            'critChance': equippedEnchantmentCritChancePercent(db, save),
            'thorns': equippedEnchantmentThornsPercent(db, save),
            'gatheringMultiplier': equippedEnchantmentGatheringMultiplier(db, save),
          }),
          isNull,
        );
      });
    }
  });

  group('enchantment tooltip parity', () {
    for (final fixture in loadParityFixtures('enchantments/tooltips')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        expect(
          checkParity(fixture, {
            'lines': db.enchantments
                .map(
                  (row) => <String, Object?>{
                    'enchantmentId': row.enchantmentId,
                    'found': getEnchantment(db, row.enchantmentId) != null,
                    'lines': enchantmentTooltipLines(db, row.enchantmentId),
                  },
                )
                .toList(),
            'unknown': enchantmentTooltipLines(db, 'ENCH-9999'),
            'none': enchantmentTooltipLines(db, null),
          }),
          isNull,
        );
      });
    }
  });
}
