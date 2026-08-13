import { withAssetVersion } from './cacheBust'

/** Empty-slot icons keyed by EquipmentSlots.Internal Key / Slot ID. */

const SLOT_KEYS: Record<string, string> = {
  'SLOT-0001': 'weapon_tool',
  'SLOT-0002': 'offhand',
  'SLOT-0003': 'helmet',
  'SLOT-0004': 'chest',
  'SLOT-0005': 'legs',
  'SLOT-0006': 'boots',
  'SLOT-0007': 'gloves',
  'SLOT-0008': 'necklace',
  'SLOT-0009': 'ring',
  'SLOT-0010': 'back',
  'SLOT-0011': 'food',
  'SLOT-0012': 'potion',
  'SLOT-0013': 'spell_1',
  'SLOT-0014': 'spell_2',
  'SLOT-0015': 'spell_3',
  'SLOT-0016': 'spell_4',
}

export function slotAssetPath(slotId: string): string {
  const key = SLOT_KEYS[slotId] ?? 'weapon_tool'
  return withAssetVersion(`/assets/icons/slots/slot_${key}.webp`)
}
