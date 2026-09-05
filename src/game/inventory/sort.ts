import type { GameDatabase, ItemRow } from '../data/types'

export type InventorySortMode = 'group' | 'az' | 'search'

export const GROUP_COMBAT = 1
export const GROUP_MINING = 2
export const GROUP_METALLURGY = 3
export const GROUP_SMITHING = 4
export const GROUP_ARTISANRY = 5
export const GROUP_COOKING = 6
export const GROUP_FISHING = 7
export const GROUP_HARVESTING = 8
export const GROUP_HUNTING = 9
export const GROUP_WOODCUTTING = 10
export const GROUP_CRAFTING = 11
export const GROUP_ALCHEMY = 12
export const GROUP_ARCANA = 13
export const GROUP_OTHER = 14

/** Display order for Codex filter chips; matches grouped bag order. */
export const INVENTORY_GROUP_ORDER = [
  GROUP_COMBAT,
  GROUP_MINING,
  GROUP_METALLURGY,
  GROUP_SMITHING,
  GROUP_ARTISANRY,
  GROUP_COOKING,
  GROUP_FISHING,
  GROUP_HARVESTING,
  GROUP_HUNTING,
  GROUP_WOODCUTTING,
  GROUP_CRAFTING,
  GROUP_ALCHEMY,
  GROUP_ARCANA,
  GROUP_OTHER,
] as const

export const INVENTORY_GROUP_LABELS: Record<number, string> = {
  [GROUP_COMBAT]: 'Combat',
  [GROUP_MINING]: 'Mining',
  [GROUP_METALLURGY]: 'Metallurgy',
  [GROUP_SMITHING]: 'Smithing',
  [GROUP_ARTISANRY]: 'Artisanry',
  [GROUP_COOKING]: 'Cooking',
  [GROUP_FISHING]: 'Fishing',
  [GROUP_HARVESTING]: 'Harvesting',
  [GROUP_HUNTING]: 'Hunting',
  [GROUP_WOODCUTTING]: 'Woodcutting',
  [GROUP_CRAFTING]: 'Crafting',
  [GROUP_ALCHEMY]: 'Alchemy',
  [GROUP_ARCANA]: 'Arcana',
  [GROUP_OTHER]: 'Other',
}

export function inventoryGroupLabel(group: number): string {
  return INVENTORY_GROUP_LABELS[group] ?? 'Other'
}

const SKILL_GROUP: Record<string, number> = {
  'SKL-0002': GROUP_MINING,
  'SKL-0003': GROUP_FISHING,
  'SKL-0004': GROUP_HARVESTING,
  'SKL-0005': GROUP_HUNTING,
  'SKL-0006': GROUP_WOODCUTTING,
  'SKL-0007': GROUP_COOKING,
  'SKL-0008': GROUP_METALLURGY,
  'SKL-0009': GROUP_CRAFTING,
  'SKL-0010': GROUP_ALCHEMY,
  'SKL-0011': GROUP_SMITHING,
  'SKL-0012': GROUP_ARTISANRY,
  'SKL-0013': GROUP_ARCANA,
}

const ARMOR_SLOT_RANK: Record<string, number> = {
  'SLOT-0003': 0,
  'SLOT-0004': 1,
  'SLOT-0005': 2,
  'SLOT-0006': 3,
  'SLOT-0007': 4,
}

const UNKNOWN_TIER = 80
const UNKNOWN_LEVEL = 999

function parseTags(value: string | null | undefined): Set<string> {
  if (!value) return new Set()
  return new Set(
    value
      .split(/[;,]/)
      .map((part) => part.trim().toLowerCase())
      .filter((part) => part.length > 0),
  )
}

function metalTier(name: string): number {
  if (name.includes('ancient alloy')) return 11
  if (name.includes('reinforced steel')) return 6
  if (name.includes('moonstone')) return 13
  if (name.includes('tungsten')) return 10
  if (name.includes('titanium')) return 9
  if (name.includes('aether')) return 12
  if (name.includes('ancient')) return 11
  if (/\bbronze\b/.test(name)) return 3
  if (/\bcopper\b/.test(name)) return 1
  if (/\btin\b/.test(name)) return 2
  if (/\biron\b/.test(name)) return 4
  if (/\bsteel\b/.test(name)) return 5
  if (/\bsilver\b/.test(name)) return 7
  if (/\bgold\b/.test(name)) return 8
  if (/\bwooden\b/.test(name) || /\bregular\b/.test(name)) return 0
  return UNKNOWN_TIER
}

function woodTier(name: string): number {
  if (name.includes('mahogany')) return 5
  if (name.includes('maple')) return 4
  if (name.includes('poplar')) return 3
  if (name.includes('oak')) return 2
  if (name.includes('cedar')) return 1
  if (name.includes('ancient')) return 6
  if (name.includes('wooden') || name.includes('regular')) return 0
  return UNKNOWN_TIER
}

function gemTier(name: string): number {
  if (name.includes('sapphire')) return 0
  if (name.includes('emerald')) return 1
  if (name.includes('ruby')) return 2
  return UNKNOWN_TIER
}

function rememberMin(map: Map<string, number>, itemId: string, level: number | null | undefined) {
  if (!itemId || typeof level !== 'number' || !Number.isFinite(level)) return
  const current = map.get(itemId)
  if (current === undefined || level < current) map.set(itemId, level)
}

/** Cached grouping ranks so a 180-slot bag does not rescan the database per compare. */
export class InventorySorter {
  private readonly items = new Map<string, ItemRow>()
  private readonly slotByItem = new Map<string, string>()
  private readonly levels = new Map<string, number>()

  constructor(db: GameDatabase) {
    for (const item of db.Items) {
      this.items.set(item['Item ID'], item)
    }
    for (const row of db.Equipment) {
      const slotId = row['Slot ID']
      if (slotId) this.slotByItem.set(row['Item ID'], slotId)
    }
    for (const action of db.Actions) {
      rememberMin(this.levels, action['Target ID'] ?? '', action['Proficiency Level'])
    }
    for (const recipe of db.Recipes) {
      rememberMin(this.levels, recipe['Output Item ID'], recipe['Proficiency Level'])
    }
    for (const project of db.Projects) {
      rememberMin(
        this.levels,
        project['Output Item / Target ID'],
        project['Required Skill 1 Level'],
      )
    }
    for (const row of db.Equipment) {
      rememberMin(this.levels, row['Item ID'], row['Required Level'])
    }
  }

  itemName(itemId: string): string {
    return this.items.get(itemId)?.['Display Name'] ?? itemId
  }

  itemMatchesName(itemId: string, query: string): boolean {
    const needle = query.trim().toLowerCase()
    if (!needle) return true
    return this.itemName(itemId).toLowerCase().includes(needle)
  }

  /** Favorites first in every mode; Search filters by display name only. */
  displayIndexes(
    stacks: Array<{ itemId: string; favorite?: boolean | null }>,
    mode: InventorySortMode,
    query = '',
  ): number[] {
    let indexes = stacks.map((_, index) => index)
    if (mode === 'search') {
      const needle = query.trim()
      if (needle) {
        indexes = indexes.filter((index) => this.itemMatchesName(stacks[index]!.itemId, needle))
      }
    }
    const compare =
      mode === 'az' ? this.compareAz.bind(this) : this.compareGrouped.bind(this)
    return indexes.sort((a, b) => compare(stacks[a]!, stacks[b]!, a, b))
  }

  compareGrouped(
    a: { itemId: string; favorite?: boolean | null },
    b: { itemId: string; favorite?: boolean | null },
    aIndex = 0,
    bIndex = 0,
  ): number {
    const favorite = this.compareFavorite(a, b)
    if (favorite !== 0) return favorite
    const keyA = this.groupedKey(a.itemId)
    const keyB = this.groupedKey(b.itemId)
    for (let i = 0; i < keyA.length; i += 1) {
      const left = keyA[i]!
      const right = keyB[i]!
      if (left < right) return -1
      if (left > right) return 1
    }
    return aIndex - bIndex
  }

  compareAz(
    a: { itemId: string; favorite?: boolean | null },
    b: { itemId: string; favorite?: boolean | null },
    aIndex = 0,
    bIndex = 0,
  ): number {
    const favorite = this.compareFavorite(a, b)
    if (favorite !== 0) return favorite
    const name = this.itemName(a.itemId).toLowerCase().localeCompare(this.itemName(b.itemId).toLowerCase())
    if (name !== 0) return name
    if (a.itemId !== b.itemId) return a.itemId < b.itemId ? -1 : 1
    return aIndex - bIndex
  }

  private compareFavorite(
    a: { favorite?: boolean | null },
    b: { favorite?: boolean | null },
  ): number {
    const af = a.favorite === true ? 0 : 1
    const bf = b.favorite === true ? 0 : 1
    return af - bf
  }

  groupedKey(itemId: string): Array<number | string> {
    const item = this.items.get(itemId)
    const name = (item?.['Display Name'] ?? itemId).toLowerCase()
    const category = (item?.Category ?? '').toLowerCase()
    const subtype = (item?.Subtype ?? '').toLowerCase()
    const tags = parseTags(item?.['Functional / Source Tags'])
    const slot = this.slotByItem.get(itemId) ?? item?.['Equipment Slot ID'] ?? ''
    const group = this.resolveGroup(item, tags, category, subtype, name)
    const family = this.family(group, tags, category, subtype, name)
    const rank = this.rank(group, family, name, itemId)
    const slotRank = ARMOR_SLOT_RANK[slot] ?? 50
    return [group, family, rank, slotRank, name, itemId]
  }

  groupOf(itemId: string): number {
    return this.groupedKey(itemId)[0] as number
  }

  private resolveGroup(
    item: ItemRow | undefined,
    tags: Set<string>,
    category: string,
    subtype: string,
    name: string,
  ): number {
    if (subtype === 'timber' || name.endsWith(' timber')) return GROUP_WOODCUTTING
    if (category === 'spell component' || category === 'spell' || tags.has('spell')) {
      return GROUP_ARCANA
    }

    const skill = item?.['Associated Skill ID']
    if (skill === 'SKL-0001') {
      if (category === 'raw food' || tags.has('cooking_input')) return GROUP_HUNTING
      return GROUP_COMBAT
    }
    if (skill && SKILL_GROUP[skill] !== undefined) return SKILL_GROUP[skill]

    if (tags.has('mining_tool')) return GROUP_MINING
    if (tags.has('fishing_tool')) return GROUP_FISHING
    if (tags.has('woodcutting_tool')) return GROUP_WOODCUTTING
    if (tags.has('hunting_tool')) return GROUP_HUNTING
    if (tags.has('metallurgy_time_modifier') || subtype.includes('metallurgy')) {
      return GROUP_METALLURGY
    }

    if (
      category === 'weapon' ||
      category === 'armor' ||
      category === 'shield / off-hand' ||
      tags.has('combat_weapon') ||
      tags.has('combat_armor') ||
      tags.has('combat_defense')
    ) {
      return GROUP_COMBAT
    }

    if (category === 'raw food' || tags.has('cooking_input') || tags.has('food_slot')) {
      if (tags.has('fishing_output')) return GROUP_FISHING
      if (tags.has('harvesting_output')) return GROUP_HARVESTING
      return GROUP_HUNTING
    }

    if (
      subtype.includes('creature') ||
      subtype.includes('hide') ||
      name.includes('leather') ||
      tags.has('hunting_output')
    ) {
      return GROUP_HUNTING
    }

    if (
      subtype.includes('forest') ||
      name.includes('heartwood') ||
      name.includes('bark') ||
      /\bsap\b/.test(name)
    ) {
      return GROUP_WOODCUTTING
    }

    if (tags.has('arcana_input') || tags.has('arcana_output') || tags.has('arcana_equipment')) {
      return GROUP_ARCANA
    }

    return GROUP_OTHER
  }

  private family(
    group: number,
    tags: Set<string>,
    category: string,
    subtype: string,
    name: string,
  ): number {
    switch (group) {
      case GROUP_COMBAT:
        if (category === 'weapon' || (tags.has('combat_weapon') && category !== 'shield / off-hand')) {
          return 0
        }
        if (category === 'shield / off-hand' || tags.has('combat_defense')) return 1
        if (category === 'armor' || tags.has('combat_armor')) return 2
        return 3
      case GROUP_MINING:
        if (tags.has('mining_tool') || subtype.includes('pickaxe') || name.includes('pickaxe')) return 0
        if (subtype.includes('ore')) return 2
        if (subtype === 'gem' || gemTier(name) !== UNKNOWN_TIER) return 3
        if (name.includes('essence') || subtype.includes('magical')) return 4
        if (
          subtype.includes('mineral') ||
          subtype.includes('fuel') ||
          name === 'clay' ||
          name === 'coal'
        ) {
          return 1
        }
        return 5
      case GROUP_FISHING:
        if (category === 'tool' || tags.has('fishing_tool')) {
          if (name.includes('rod')) return 0
          if (name.includes('net')) return 1
          if (name.includes('harpoon')) return 2
          return 3
        }
        if (category === 'raw food' || tags.has('fishing_output')) return 4
        return 5
      case GROUP_HARVESTING:
        if (subtype.includes('crop')) return 0
        if (
          subtype.includes('herb') ||
          subtype.includes('weed') ||
          name.includes('blossom') ||
          subtype.includes('wild plant')
        ) {
          return 1
        }
        return 2
      case GROUP_HUNTING:
        if (tags.has('hunting_tool') || category === 'tool' || name.includes('bow')) return 0
        if (subtype.includes('hide') || name.includes('leather') || subtype.includes('processed')) {
          return 1
        }
        if (category === 'raw food' || name.includes('meat') || name.includes('beef') || name.includes('venison')) {
          return 2
        }
        return 3
      case GROUP_WOODCUTTING:
        if (tags.has('woodcutting_tool') || name.includes('hatchet') || /\baxe\b/.test(name)) return 0
        if (subtype === 'log' || name.endsWith(' log')) return 1
        if (subtype === 'timber' || name.endsWith(' timber')) return 2
        return 3
      case GROUP_COOKING:
        if (category === 'food' || tags.has('cooking_output') || tags.has('food_slot')) return 0
        if (category === 'armor' || category === 'tool') return 1
        return 2
      case GROUP_METALLURGY:
        if (category === 'tool' || name.includes('warhammer')) return 0
        if (category === 'metal bar' || tags.has('metallurgy_output') || name.endsWith(' bar')) return 1
        return 2
      case GROUP_CRAFTING:
        if (category === 'component') return 0
        return 1
      case GROUP_ALCHEMY:
        if (category === 'potion' || tags.has('alchemy_output')) return 0
        return 1
      case GROUP_SMITHING:
        if (category === 'tool') return 0
        if (category === 'weapon') return 1
        if (category === 'shield / off-hand') return 2
        if (category === 'armor') return 3
        return 4
      case GROUP_ARTISANRY:
        if (category === 'weapon' || category === 'tool' || tags.has('hunting_tool')) return 0
        if (category === 'jewelry') return 2
        if (category === 'armor') return 1
        return 3
      case GROUP_ARCANA:
        if (category === 'spell component' || name.includes('tablet') || name.includes('essence')) {
          return 0
        }
        if (category === 'spell' || tags.has('spell')) return 1
        if (name.includes('staff') || name.includes('wand')) return 2
        return 3
      default:
        return 0
    }
  }

  private rank(group: number, family: number, name: string, itemId: string): number {
    if (group === GROUP_MINING) {
      if (family === 0 || family === 2) return metalTier(name)
      if (family === 3) return gemTier(name)
      return 0
    }
    if (group === GROUP_WOODCUTTING) {
      if (family === 0) return metalTier(name)
      if (family === 1 || family === 2) return woodTier(name)
      return 0
    }
    if (group === GROUP_METALLURGY || group === GROUP_SMITHING) return metalTier(name)
    if (group === GROUP_ARTISANRY) {
      const wood = woodTier(name)
      if (wood !== UNKNOWN_TIER) return wood
      const gem = gemTier(name)
      if (gem !== UNKNOWN_TIER) return gem
      return metalTier(name)
    }
    if (
      group === GROUP_FISHING ||
      group === GROUP_HARVESTING ||
      group === GROUP_COOKING ||
      group === GROUP_ALCHEMY ||
      group === GROUP_HUNTING
    ) {
      return this.levels.get(itemId) ?? UNKNOWN_LEVEL
    }
    if (group === GROUP_ARCANA) return this.levels.get(itemId) ?? UNKNOWN_LEVEL
    if (group === GROUP_COMBAT) {
      const metal = metalTier(name)
      if (metal !== UNKNOWN_TIER) return metal
      return this.levels.get(itemId) ?? UNKNOWN_LEVEL
    }
    return 0
  }
}

export function inventoryDisplayIndexes(
  db: GameDatabase,
  stacks: Array<{ itemId: string; favorite?: boolean | null }>,
  mode: InventorySortMode,
  query = '',
): number[] {
  return new InventorySorter(db).displayIndexes(stacks, mode, query)
}
