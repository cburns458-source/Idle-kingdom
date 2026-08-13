import {
  autoEquipPromptView,
  missingToolCapabilities,
  proposeAutoEquipForActivity,
  toolCapabilitiesRequiredForActivity,
} from '../../game/equipment/autoEquip'
import {
  equipInventoryIndex,
  equipItemFromInventory,
  equipStackToSlot,
  equipmentRequirementFailure,
  equippedActionTimeReductionPercent,
  isDaggerItem,
  isStackableConsumableSlot,
  slotItemId,
  unequipSlot,
  type EquipResult,
} from '../../game/equipment/loadout'
import { equipmentForItemId, equipmentTooltipStatLines } from '../../game/equipment/tooltips'
import { withRecalculatedVitals } from '../../game/equipment/vitals'
import type { EquippedStack, PlayerSave } from '../../game/save/types'
import { scenario, type JsonValue, type ParityScenario } from '../types'
import { contentDatabase } from './contentDatabase'
import { asJson, baseSave, gearedSave, richSave } from './saveFixtures'

/**
 * Variants of the geared save, each isolating one equip branch: a shield to
 * displace, a main-hand dagger that blocks the off-hand, skills too low for the
 * gear in the bag, and no free spell slot.
 */
type SaveKind = 'base' | 'rich' | 'geared' | 'shielded' | 'dagger-mainhand' | 'unskilled' | 'spells-full'

function withSlot(save: PlayerSave, slotId: string, stack: EquippedStack): PlayerSave {
  return { ...save, equipment: { slots: { ...save.equipment.slots, [slotId]: stack } } }
}

function saveFor(kind: SaveKind): PlayerSave {
  const db = contentDatabase()
  switch (kind) {
    case 'base':
      return baseSave(db)
    case 'rich':
      return richSave(db)
    case 'geared':
      return gearedSave(db)
    case 'shielded':
      return withSlot(gearedSave(db), 'SLOT-0002', { itemId: 'ITEM-0148', quantity: 1 })
    case 'dagger-mainhand':
      return withSlot(gearedSave(db), 'SLOT-0001', { itemId: 'ITEM-0125', quantity: 1 })
    case 'spells-full':
      return withSlot(gearedSave(db), 'SLOT-0016', { itemId: 'ITEM-0297', quantity: 1 })
    case 'unskilled': {
      const geared = gearedSave(db)
      return { ...geared, skills: geared.skills.map((skill) => ({ ...skill, level: 1, xp: 0 })) }
    }
  }
}

function withSave(kind: SaveKind, extra: Record<string, JsonValue> = {}): JsonValue {
  return { source: 'content', save: asJson(saveFor(kind)), ...extra }
}

function resultJson(result: EquipResult): JsonValue {
  return result.ok
    ? { ok: true, save: asJson(result.save) }
    : ({ ok: false, reason: result.reason } as JsonValue)
}

/** Every branch of the equip flow: gear swap, spells, daggers, consumables. */
const EQUIP_ITEM_CASES: Array<{ name: string; save: SaveKind; itemId: string }> = [
  { name: 'equips-into-empty-slot', save: 'geared', itemId: 'ITEM-0170' },
  { name: 'swaps-occupied-slot', save: 'geared', itemId: 'ITEM-0114' },
  { name: 'offhand-dagger-blocked-by-mainhand-dagger', save: 'dagger-mainhand', itemId: 'ITEM-0129' },
  { name: 'offhand-dagger-replaces-shield', save: 'shielded', itemId: 'ITEM-0129' },
  { name: 'spell-fills-first-empty-slot', save: 'geared', itemId: 'ITEM-0295' },
  { name: 'spell-slots-full', save: 'spells-full', itemId: 'ITEM-0295' },
  { name: 'food-stack-moves-whole-stack', save: 'geared', itemId: 'ITEM-0059' },
  { name: 'potion-stack-keeps-favorite', save: 'geared', itemId: 'ITEM-0070' },
  { name: 'requirement-not-met', save: 'unskilled', itemId: 'ITEM-0114' },
  { name: 'not-equippable', save: 'rich', itemId: 'ITEM-0025' },
  { name: 'not-in-inventory', save: 'base', itemId: 'ITEM-0131' },
  { name: 'enchanted-item-keeps-enchantment', save: 'geared', itemId: 'ITEM-0100' },
]

const EQUIP_INDEX_CASES: Array<{ name: string; save: SaveKind; index: number }> = [
  { name: 'first-stack', save: 'geared', index: 0 },
  { name: 'enchanted-stack', save: 'geared', index: 6 },
  { name: 'favorited-potion-stack', save: 'geared', index: 7 },
  { name: 'negative-index', save: 'geared', index: -1 },
  { name: 'out-of-range', save: 'geared', index: 99 },
  { name: 'fractional-index', save: 'geared', index: 1.5 },
]

const UNEQUIP_SLOTS = [
  'SLOT-0001',
  'SLOT-0002',
  'SLOT-0011',
  'SLOT-0013',
  'SLOT-0004',
  'SLOT-9999',
]

/** One activity per tool capability in the database, plus two with none. */
const AUTO_EQUIP_ACTIVITIES = [
  'ACT-0005',
  'ACT-0016',
  'ACT-0009',
  'ACT-0003',
  'ACT-0001',
  'NOPE-0000',
]

export const equipmentScenarios: ParityScenario[] = [
  ...EQUIP_ITEM_CASES.map((entry) =>
    scenario(
      'equipment/equip-item',
      entry.name,
      withSave(entry.save, { itemId: entry.itemId }),
      () => resultJson(equipItemFromInventory(contentDatabase(), saveFor(entry.save), entry.itemId)),
    ),
  ),

  ...EQUIP_INDEX_CASES.map((entry) =>
    scenario(
      'equipment/equip-index',
      entry.name,
      withSave(entry.save, { index: entry.index }),
      () => resultJson(equipInventoryIndex(contentDatabase(), saveFor(entry.save), entry.index)),
    ),
  ),

  ...UNEQUIP_SLOTS.map((slotId) =>
    scenario(
      'equipment/unequip',
      slotId.toLowerCase(),
      withSave('geared', { slotId }),
      () => resultJson(unequipSlot(saveFor('geared'), slotId)),
    ),
  ),

  scenario('equipment/force-set', 'replaces-weapon', withSave('geared'), () => ({
    save: asJson(equipStackToSlot(saveFor('geared'), 'SLOT-0001', 'ITEM-0114', 1)),
  })),
  scenario('equipment/force-set', 'zero-quantity-unequips', withSave('geared'), () => ({
    save: asJson(equipStackToSlot(saveFor('geared'), 'SLOT-0001', 'ITEM-0114', 0)),
  })),
  scenario('equipment/force-set', 'consumes-matching-inventory', withSave('geared'), () => ({
    save: asJson(equipStackToSlot(saveFor('geared'), 'SLOT-0011', 'ITEM-0059', 5)),
  })),

  // Every equipment row, so requirement text and tooltip formatting are covered
  // for the real content rather than a hand-picked sample.
  ...(['base', 'geared'] as const).map((kind) =>
    scenario('equipment/rows', `all-rows-${kind}-save`, withSave(kind), () => {
      const db = contentDatabase()
      const save = saveFor(kind)
      return {
        rows: db.Equipment.map((equipment) => ({
          itemId: equipment['Item ID'],
          requirementFailure: equipmentRequirementFailure(db, save, equipment),
          tooltip: equipmentTooltipStatLines(equipment),
          dagger: isDaggerItem(db, equipment['Item ID']),
          consumableSlot: isStackableConsumableSlot(equipment['Slot ID'] ?? ''),
        })),
      } as unknown as JsonValue
    }),
  ),

  scenario('equipment/lookup', 'missing-item', { source: 'content' }, () => ({
    found: equipmentForItemId(contentDatabase(), 'ITEM-9999') != null,
    tooltip: equipmentTooltipStatLines(undefined),
  })),

  ...(['base', 'rich', 'geared'] as const).map((kind) =>
    scenario('equipment/summary', kind, withSave(kind), () => {
      const db = contentDatabase()
      const save = saveFor(kind)
      return {
        actionTimeReduction: equippedActionTimeReductionPercent(db, save),
        mainhand: slotItemId(save, 'SLOT-0001'),
        offhand: slotItemId(save, 'SLOT-0002'),
        vitals: asJson(withRecalculatedVitals(db, save)),
      } as unknown as JsonValue
    }),
  ),

  ...AUTO_EQUIP_ACTIVITIES.flatMap((activityId) =>
    (['base', 'geared', 'unskilled'] as const).map((kind) =>
      scenario(
        'equipment/auto-equip',
        `${activityId}-${kind}`.toLowerCase(),
        withSave(kind, { activityId }),
        () => {
          const db = contentDatabase()
          const save = saveFor(kind)
          const proposal = proposeAutoEquipForActivity(db, save, activityId, 'blocked')
          return {
            required: toolCapabilitiesRequiredForActivity(db, activityId),
            missing: missingToolCapabilities(db, save, activityId),
            proposal: proposal == null ? null : { ...proposal },
            prompt: proposal == null ? null : autoEquipPromptView(proposal),
          } as unknown as JsonValue
        },
      ),
    ),
  ),
]
