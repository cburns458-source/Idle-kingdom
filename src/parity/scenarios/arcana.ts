import {
  applyEnchantmentToTarget,
  decodeEnchantTarget,
  eligibleEnchantmentTargets,
  encodeEnchantTarget,
  enchantmentTooltipLines,
  equippedEnchantmentCritChancePercent,
  equippedEnchantmentDamageBonus,
  equippedEnchantmentGatheringMultiplier,
  equippedEnchantmentThornsPercent,
  isAxeItem,
  type EnchantTarget,
} from '../../game/projects/enchantments'
import { getEnchantment } from '../../game/projects/projects'
import type { PlayerSave } from '../../game/save/types'
import {
  activeSpellDamageRangeMultiplier,
  activeSpellItemDoubleChancePercent,
  combineSpellPercentBonuses,
  equippedSpellStacks,
  firstEmptySpellSlot,
  isSpellEquipment,
  isSpellItem,
  isSpellSlotId,
  spellDamageRangeBonusPercent,
  spellEffectEnchantmentId,
  spellItemDoubleChancePercent,
  spellTooltipLines,
  SPELL_SLOT_IDS,
} from '../../game/spells/spells'
import { scenario, type JsonValue, type ParityScenario } from '../types'
import { contentDatabase } from './contentDatabase'
import { asJson, baseSave, gearedSave, richSave } from './saveFixtures'

type SaveKind = 'base' | 'rich' | 'geared'

function saveFor(kind: SaveKind): PlayerSave {
  const db = contentDatabase()
  if (kind === 'base') return baseSave(db)
  if (kind === 'rich') return richSave(db)
  return gearedSave(db)
}

function withSave(kind: SaveKind, extra: Record<string, JsonValue> = {}): JsonValue {
  return { source: 'content', save: asJson(saveFor(kind)), ...extra }
}

const TARGET_CODES = [
  'eq:SLOT-0001',
  'inv:0',
  'inv:12',
  'inv:-1',
  'inv:1.5',
  'inv:abc',
  'SLOT-0004',
  'nonsense',
  '',
]

const APPLY_TARGETS: Array<{ name: string; save: SaveKind; target: EnchantTarget }> = [
  { name: 'equipped-single', save: 'rich', target: { kind: 'equipped', slotId: 'SLOT-0001' } },
  { name: 'equipped-already-enchanted', save: 'geared', target: { kind: 'equipped', slotId: 'SLOT-0001' } },
  { name: 'equipped-empty-slot', save: 'geared', target: { kind: 'equipped', slotId: 'SLOT-0004' } },
  { name: 'equipped-stack-splits', save: 'geared', target: { kind: 'equipped', slotId: 'SLOT-0011' } },
  { name: 'inventory-single', save: 'geared', target: { kind: 'inventory', index: 0 } },
  { name: 'inventory-stack-splits', save: 'geared', target: { kind: 'inventory', index: 5 } },
  { name: 'inventory-already-enchanted', save: 'geared', target: { kind: 'inventory', index: 6 } },
  { name: 'inventory-out-of-range', save: 'geared', target: { kind: 'inventory', index: 99 } },
]

export const arcanaScenarios: ParityScenario[] = [
  scenario('spells/slots', 'slot-ids', { source: 'content' }, () => ({
    slotIds: [...SPELL_SLOT_IDS],
    recognized: SPELL_SLOT_IDS.map((slotId) => isSpellSlotId(slotId)),
    rejected: isSpellSlotId('SLOT-0001'),
  })),

  // Every equipment and item row, so spell detection is exercised against real content.
  scenario('spells/detection', 'all-rows', { source: 'content' }, () => {
    const db = contentDatabase()
    return {
      equipment: db.Equipment.map((row) => ({
        itemId: row['Item ID'],
        spellEquipment: isSpellEquipment(row),
      })),
      items: db.Items.map((row) => ({
        itemId: row['Item ID'],
        spellItem: isSpellItem(db, row['Item ID']),
        effectEnchantmentId: spellEffectEnchantmentId(db, row['Item ID']),
        damageRangeBonus: spellDamageRangeBonusPercent(db, row['Item ID']),
        itemDoubleChance: spellItemDoubleChancePercent(db, row['Item ID']),
      })),
    } as unknown as JsonValue
  }),

  scenario('spells/tooltips', 'spell-items', { source: 'content' }, () => {
    const db = contentDatabase()
    return {
      lines: db.Items.filter((row) => isSpellItem(db, row['Item ID'])).map((row) => ({
        itemId: row['Item ID'],
        lines: spellTooltipLines(db, row, row['Item ID']),
      })),
    } as unknown as JsonValue
  }),

  ...(['base', 'rich', 'geared'] as const).map((kind) =>
    scenario('spells/equipped', kind, withSave(kind), () => {
      const db = contentDatabase()
      const save = saveFor(kind)
      return {
        stacks: equippedSpellStacks(save),
        firstEmpty: firstEmptySpellSlot(save),
        damageMultiplier: activeSpellDamageRangeMultiplier(db, save),
        doubleChance: activeSpellItemDoubleChancePercent(db, save),
      } as unknown as JsonValue
    }),
  ),

  scenario(
    'spells/combine',
    'stacking-and-unique',
    {
      source: 'content',
      contributions: [
        { percent: 10, stacks: true },
        { percent: 10, stacks: true },
        { percent: 25, stacks: false },
        { percent: 15, stacks: false },
        { percent: 0, stacks: true },
        { percent: -5, stacks: false },
      ],
    },
    () => ({
      combined: combineSpellPercentBonuses([
        { percent: 10, stacks: true },
        { percent: 10, stacks: true },
        { percent: 25, stacks: false },
        { percent: 15, stacks: false },
        { percent: 0, stacks: true },
        { percent: -5, stacks: false },
      ]),
      empty: combineSpellPercentBonuses([]),
    }),
  ),

  scenario('enchantments/axe-detection', 'all-equipment', { source: 'content' }, () => {
    const db = contentDatabase()
    return {
      rows: db.Equipment.map((equipment) => ({
        itemId: equipment['Item ID'],
        axe: isAxeItem(
          db.Items.find((item) => item['Item ID'] === equipment['Item ID']),
          equipment,
        ),
      })),
    } as unknown as JsonValue
  }),

  scenario('enchantments/targets', 'codec', { source: 'content', codes: TARGET_CODES }, () => ({
    decoded: TARGET_CODES.map((code) => {
      const target = decodeEnchantTarget(code)
      return {
        code,
        target,
        reencoded: target == null ? null : encodeEnchantTarget(target),
      }
    }),
  })),

  // Every enchantment row against every save, so target eligibility covers all
  // Valid Target strings in the real database.
  ...(['rich', 'geared'] as const).map((kind) =>
    scenario('enchantments/eligible', kind, withSave(kind), () => {
      const db = contentDatabase()
      const save = saveFor(kind)
      return {
        byEnchantment: db.Enchantments.map((enchantment) => ({
          enchantmentId: enchantment['Enchantment ID'],
          options: eligibleEnchantmentTargets(db, save, enchantment),
        })),
      } as unknown as JsonValue
    }),
  ),

  ...APPLY_TARGETS.map((entry) =>
    scenario(
      'enchantments/apply',
      entry.name,
      withSave(entry.save, { target: entry.target as unknown as JsonValue }),
      () => {
        const applied = applyEnchantmentToTarget(saveFor(entry.save), entry.target, 'ENCH-0003')
        return { save: applied == null ? null : asJson(applied) } as unknown as JsonValue
      },
    ),
  ),

  ...(['base', 'rich', 'geared'] as const).map((kind) =>
    scenario('enchantments/bonuses', kind, withSave(kind), () => {
      const db = contentDatabase()
      const save = saveFor(kind)
      return {
        damageBonus: equippedEnchantmentDamageBonus(db, save),
        critChance: equippedEnchantmentCritChancePercent(db, save),
        thorns: equippedEnchantmentThornsPercent(db, save),
        gatheringMultiplier: equippedEnchantmentGatheringMultiplier(db, save),
      }
    }),
  ),

  scenario('enchantments/tooltips', 'all-rows', { source: 'content' }, () => {
    const db = contentDatabase()
    return {
      lines: db.Enchantments.map((row) => ({
        enchantmentId: row['Enchantment ID'],
        found: getEnchantment(db, row['Enchantment ID']) != null,
        lines: enchantmentTooltipLines(db, { itemId: 'ITEM-0100', quantity: 1, enchantmentId: row['Enchantment ID'] }),
      })),
      unknown: enchantmentTooltipLines(db, {
        itemId: 'ITEM-0100',
        quantity: 1,
        enchantmentId: 'ENCH-9999',
      }),
      none: enchantmentTooltipLines(db, { itemId: 'ITEM-0100', quantity: 1 }),
    } as unknown as JsonValue
  }),
]
