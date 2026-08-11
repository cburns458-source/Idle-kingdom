import type { ItemRow } from '../data/types'
import { withAssetVersion } from './cacheBust'

/** Specific item overrides (Item ID -> icon file stem under /assets/icons/items/). */
const ITEM_ID_ICONS: Record<string, string> = {
  'ITEM-0001': 'gold',
  'ITEM-0006': 'coal',
  'ITEM-0011': 'essence',
  'ITEM-0025': 'potato',
  'ITEM-0026': 'potato',
  'ITEM-0028': 'berries',
  'ITEM-0046': 'dragon_scale',
  'ITEM-0058': 'baked_potato',
  'ITEM-0103': 'fishing_tool',
  'ITEM-0108': 'net',
  'ITEM-0111': 'copper_pickaxe',
  'ITEM-0119': 'steel_pickaxe',
  'ITEM-0123': 'hammer',
  'ITEM-0169': 'backpack',
  'ITEM-0288': 'insignia',
  'ITEM-0295': 'spell',
  'ITEM-0296': 'cosmetic_outfit_travelers_tunic',
}

/** Resolve an icon path for an item using ID, then category/subtype heuristics. */
export function itemAssetPath(item: ItemRow | string | undefined): string {
  if (!item) return withAssetVersion('/assets/icons/items/item_default.png')
  if (typeof item === 'string') {
    const stem = ITEM_ID_ICONS[item] ?? 'default'
    return withAssetVersion(`/assets/icons/items/item_${stem}.png`)
  }

  const byId = ITEM_ID_ICONS[item['Item ID']]
  if (byId) return withAssetVersion(`/assets/icons/items/item_${byId}.png`)

  const key = (item['Internal Key'] ?? '').toLowerCase()
  const category = (item.Category ?? '').toLowerCase()
  const subtype = (item.Subtype ?? '').toLowerCase()
  const blob = `${key} ${category} ${subtype} ${item['Display Name']?.toLowerCase() ?? ''}`

  const stem = iconStemFromText(blob, category, subtype)
  return withAssetVersion(`/assets/icons/items/item_${stem}.png`)
}

function iconStemFromText(blob: string, category: string, subtype: string): string {
  if (blob.includes('gold') && (category.includes('currency') || blob.includes('coin'))) return 'gold'
  if (blob.includes('essence')) return 'essence'
  if (blob.includes('coal')) return 'coal'
  if (blob.includes('potato') || blob.includes('spud')) {
    return blob.includes('baked') ? 'baked_potato' : 'potato'
  }
  if (blob.includes('backpack') || blob.includes('back item') || subtype.includes('back')) {
    return 'backpack'
  }
  if (blob.includes('fishing') || blob.includes('rod') || blob.includes('harpoon')) {
    return 'fishing_tool'
  }
  if (blob.includes('warhammer') || blob.includes('hammer')) return 'hammer'
  if (blob.includes('necklace') || blob.includes('amulet')) return 'necklace'
  if (/\bring\b/.test(blob) || subtype.includes('ring')) return 'ring'
  if (
    blob.includes('sapphire') ||
    blob.includes('emerald') ||
    blob.includes('ruby') ||
    blob.includes('gem')
  ) {
    return 'gem'
  }
  if (blob.includes('timber') || blob.includes('plank')) return 'timber'
  if (
    blob.includes('leather') ||
    blob.includes('strap') ||
    blob.includes('cloth') ||
    blob.includes('component') ||
    blob.includes('tablet') ||
    blob.includes('chain') ||
    blob.includes('clasp') ||
    blob.includes('fiber') ||
    category.includes('component')
  ) {
    return 'component'
  }
  if (blob.includes('net') || blob.includes('sling')) return 'net'
  if (blob.includes('pickaxe') || /\bpick\b/.test(blob)) return 'pickaxe'
  if (blob.includes('hatchet')) return 'hatchet'
  if (blob.includes('bow')) return 'bow'
  if (blob.includes('sword')) return 'sword'
  if (blob.includes('dagger')) return 'dagger'
  if (blob.includes('axe') && !blob.includes('pickaxe')) return 'axe'
  if (blob.includes('shield') || blob.includes('off-hand') || blob.includes('offhand')) {
    return 'shield'
  }
  if (blob.includes('helmet') || blob.includes('hat')) return 'helmet'
  // Legs before chest so "platelegs" does not resolve as chest plate.
  if (blob.includes('leg') || blob.includes('plateleg') || subtype.includes('plateleg')) {
    return 'legs'
  }
  if (blob.includes('chest') || blob.includes('plate') || blob.includes('mail')) return 'chest'
  if (blob.includes('boot')) return 'boots'
  if (blob.includes('glove')) return 'gloves'
  if (blob.includes('potion') || blob.includes('vial')) return 'potion'
  if (/\bore\b/.test(blob) || subtype.includes('ore') || category.includes('ore')) return 'ore'
  if (blob.includes('bar') || category.includes('metal bar')) return 'bar'
  if (blob.includes('log') || blob.includes('wood')) return 'log'
  if (blob.includes('herb') || blob.includes('fern') || blob.includes('weed')) return 'herb'
  if (
    blob.includes('hide') ||
    blob.includes('meat') ||
    blob.includes('feather') ||
    blob.includes('creature') ||
    blob.includes('bone')
  ) {
    return 'creature'
  }
  if (
    blob.includes('berry') ||
    blob.includes('berrie') ||
    blob.includes('grape') ||
    blob.includes('carrot') ||
    blob.includes('clay') ||
    blob.includes('root')
  ) {
    return 'raw_food'
  }
  if (blob.includes('dragon') && blob.includes('scale')) return 'dragon_scale'
  if (blob.includes('insignia')) return 'insignia'
  // Prepared spells only — not "Spell Component" tablets.
  if (category === 'spell') return 'spell'
  if (category.includes('food') || subtype.includes('food')) return 'food'
  if (category.includes('raw')) return 'raw_food'
  if (category.includes('weapon') || category.includes('tool')) return 'sword'
  if (category.includes('armor')) return 'chest'
  return 'default'
}
