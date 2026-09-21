import { equipmentForItemId, equipmentTooltipStatLines } from '../equipment/tooltips'
import type { ActionRow, EnemyRow, FacilityRow, GameDatabase } from '../data/types'
import {
  INVENTORY_GROUP_ORDER,
  InventorySorter,
  inventoryGroupLabel,
} from '../inventory/sort'
import { recipeIngredients } from '../production/recipes'
import { projectInputs } from '../projects/projects'
import { shopStockEntries } from '../shops/shops'
import { isSpellItem, spellTooltipLines } from '../spells/spells'

export { INVENTORY_GROUP_ORDER, inventoryGroupLabel }

/** How an item enters the world. New kinds can be appended without rewriting pages. */
export type CodexObtainKind = 'action' | 'enemy' | 'shop' | 'starter' | 'quest'

const GOLDEN_SPUD_ITEM_ID = 'ITEM-0026'
const CHEF_HAT_ITEM_ID = 'ITEM-0165'
const HIDE_FROM_CODEX_ACTION_ID = 'ACN-0036'
const MINING_SKILL_ID = 'SKL-0002'
const ORE_GEM_TABLE_IDS = new Set(['RWT-0058', 'RWT-0059', 'RWT-0060'])

function notesHideFromCodex(notes: unknown): boolean {
  if (typeof notes !== 'string') return false
  return /HideFromCodex|MysteryDrop/i.test(notes)
}

function hideActionFromCodex(action: ActionRow): boolean {
  if (action['Action ID'] === HIDE_FROM_CODEX_ACTION_ID || notesHideFromCodex(action.Notes)) {
    return true
  }
  return action.Category === 'Gathering' && action.Status === 'Needs Data'
}

function combatEnemyId(action: ActionRow): string | null {
  if (action.Category !== 'Combat') return null
  if (action['Target Type'] === 'Enemy' && action['Target ID']) return action['Target ID']
  return null
}

/**
 * Quest rewards in Obtained from: non-cosmetic gear/tools only (Tool / Weapon / Armor).
 * Category Cosmetic is omitted; Chef's Hat (ITEM-0165) is also omitted as vanity headwear.
 */
function includeQuestRewardAsObtainSource(category: string | null | undefined, itemId: string): boolean {
  if (itemId === CHEF_HAT_ITEM_ID) return false
  if (category === 'Cosmetic') return false
  return category === 'Tool' || category === 'Weapon' || category === 'Armor'
}

/** Pets, cosmetics, and quest-key items stay in the database; they stay out of the Codex. */
export function includeInCodexCatalog(item: {
  Category?: string | null
  Subtype?: string | null
  category?: string | null
  subtype?: string | null
}): boolean {
  const subtype = item.Subtype ?? item.subtype
  const category = item.Category ?? item.category
  if (subtype === 'Pet') return false
  if (category === 'Cosmetic' || category === 'Quest') return false
  return true
}

export interface CodexItemRef {
  itemId: string
  displayName: string
  minQuantity?: number | null
  maxQuantity?: number | null
  weight?: number | null
  /** Weight share of the reward table, as a percent (0–100). */
  dropRatePercent?: number | null
}

export interface CodexEnemyRef {
  enemyId: string
  displayName: string
}

export interface CodexLocationRef {
  locationId: string
  displayName: string
}

export interface CodexObtainSource {
  kind: CodexObtainKind
  title: string
  detail?: string | null
  actionId?: string | null
  enemyId?: string | null
  shopId?: string | null
  questId?: string | null
  locations: CodexLocationRef[]
  dropChance?: number | null
  minQuantity?: number | null
  maxQuantity?: number | null
}

export interface CodexCraft {
  id: string
  isProject: boolean
  displayName: string
  skillId: string
  skillName: string
  level?: number | null
  facilityName?: string | null
  output: CodexItemRef
  ingredients: CodexItemRef[]
}

export interface CodexItemEntry {
  itemId: string
  displayName: string
  category?: string | null
  subtype?: string | null
  description?: string | null
  group: number
  groupLabel: string
  statLines: string[]
  obtainedFrom: CodexObtainSource[]
  craftedBy: CodexCraft[]
  usedIn: CodexCraft[]
}

export interface CodexEnemyEntry {
  enemyId: string
  displayName: string
  combatLevel?: number | null
  maximumHp: number
  minDamage: number
  maxDamage: number
  combatXp?: number | null
  /** Skill name shown beside XP (Fishing for Mother Squid / Squidlings). */
  xpSkillLabel: string
  minimumGold?: number | null
  maximumGold?: number | null
  dropChance?: number | null
  locations: CodexLocationRef[]
  drops: CodexItemRef[]
}

export interface CodexActionDropTable {
  label: 'Primary' | 'Secondary' | 'Tertiary' | 'Drops' | 'Gems'
  tableId: string
  dropChance: number | null
  drops: CodexItemRef[]
}

export interface CodexActionEntry {
  actionId: string
  displayName: string
  category?: string | null
  skillId?: string | null
  skillName?: string | null
  level?: number | null
  locations: CodexLocationRef[]
  target?: CodexItemRef | null
  tables: CodexActionDropTable[]
}

function obtainKey(source: CodexObtainSource): string {
  return [
    source.kind,
    source.actionId ?? '',
    source.enemyId ?? '',
    source.shopId ?? '',
    source.questId ?? '',
    source.title,
  ].join('|')
}

/** Reverse indexes over whatever database is passed in. */
export class CodexIndex {
  private readonly db: GameDatabase
  private readonly sorter: InventorySorter
  private readonly itemsById = new Map<string, CodexItemEntry>()
  private readonly enemiesById = new Map<string, CodexEnemyEntry>()
  private readonly actionsById = new Map<string, CodexActionEntry>()
  private readonly itemOrder: string[] = []
  private readonly enemyOrder: string[] = []
  private readonly actionOrder: string[] = []

  constructor(db: GameDatabase) {
    this.db = db
    this.sorter = new InventorySorter(db)
    this.build()
  }

  get items(): CodexItemEntry[] {
    return this.itemOrder.map((id) => this.itemsById.get(id)!)
  }

  get enemies(): CodexEnemyEntry[] {
    return this.enemyOrder.map((id) => this.enemiesById.get(id)!)
  }

  get actions(): CodexActionEntry[] {
    return this.actionOrder.map((id) => this.actionsById.get(id)!)
  }

  item(itemId: string): CodexItemEntry | undefined {
    return this.itemsById.get(itemId)
  }

  enemy(enemyId: string): CodexEnemyEntry | undefined {
    return this.enemiesById.get(enemyId)
  }

  action(actionId: string): CodexActionEntry | undefined {
    return this.actionsById.get(actionId)
  }

  itemsMatching(group?: number | null, query = ''): CodexItemEntry[] {
    const needle = query.trim()
    return this.itemOrder
      .map((id) => this.itemsById.get(id)!)
      .filter((entry) => (group == null || entry.group === group) && this.sorter.itemMatchesName(entry.itemId, needle))
  }

  enemiesMatching(query = ''): CodexEnemyEntry[] {
    const needle = query.trim().toLowerCase()
    return this.enemyOrder
      .map((id) => this.enemiesById.get(id)!)
      .filter((entry) => !needle || entry.displayName.toLowerCase().includes(needle))
  }

  actionsMatching(query = ''): CodexActionEntry[] {
    const needle = query.trim().toLowerCase()
    return this.actionOrder
      .map((id) => this.actionsById.get(id)!)
      .filter((entry) => {
        if (!needle) return true
        return (
          entry.displayName.toLowerCase().includes(needle) ||
          (entry.skillName ?? '').toLowerCase().includes(needle)
        )
      })
  }

  private build() {
    const names = new Map(this.db.Items.map((item) => [item['Item ID'], item['Display Name']]))
    const enemyNames = new Map(
      this.db.Enemies.map((enemy) => [enemy['Enemy ID'], enemy['Display Name']]),
    )
    const skills = new Map(this.db.Skills.map((skill) => [skill['Skill ID'], skill['Display Name']]))
    const locations = new Map(
      this.db.Locations.map((location) => [location['Location ID'], location['Display Name']]),
    )
    const facilities = new Map<string, FacilityRow>(
      this.db.Facilities.map((facility) => [facility['Facility ID'], facility]),
    )
    const actionLocations = this.actionLocations(locations)
    const tableItems = this.rewardItems(names)

    const obtained = new Map<string, CodexObtainSource[]>()
    const craftedBy = new Map<string, CodexCraft[]>()
    const usedIn = new Map<string, CodexCraft[]>()

    const addObtain = (itemId: string | null | undefined, source: CodexObtainSource) => {
      if (!itemId || !names.has(itemId)) return
      if (itemId === GOLDEN_SPUD_ITEM_ID) return
      const list = obtained.get(itemId) ?? []
      const key = obtainKey(source)
      if (list.some((row) => obtainKey(row) === key)) return
      list.push(source)
      obtained.set(itemId, list)
    }

    const addCraft = (craft: CodexCraft) => {
      if (names.has(craft.output.itemId)) {
        const list = craftedBy.get(craft.output.itemId) ?? []
        list.push(craft)
        craftedBy.set(craft.output.itemId, list)
      }
      for (const ingredient of craft.ingredients) {
        if (!names.has(ingredient.itemId)) continue
        const list = usedIn.get(ingredient.itemId) ?? []
        list.push(craft)
        usedIn.set(ingredient.itemId, list)
      }
    }

    for (const enemy of this.db.Enemies) {
      const tableId = enemy['Reward Table ID']
      if (!tableId) continue
      const locs = this.enemyLocations(enemy, actionLocations, locations)
      for (const drop of tableItems.get(tableId) ?? []) {
        addObtain(drop.itemId, {
          kind: 'enemy',
          title: enemy['Display Name'],
          enemyId: enemy['Enemy ID'],
          locations: locs,
          dropChance: enemy['Drop Chance'],
          minQuantity: drop.minQuantity,
          maxQuantity: drop.maxQuantity,
        })
      }
    }

    for (const action of this.db.Actions) {
      if (action.Category === 'Standard Production') continue
      if (hideActionFromCodex(action)) continue
      const locs = actionLocations.get(action['Action ID']) ?? []
      const skillName = skills.get(action['Relevant Skill ID'])
      const level = action['Proficiency Level']
      const detailParts = [
        skillName ? skillName : null,
        typeof level === 'number' ? `Level ${level}` : null,
      ].filter((part): part is string => !!part)
      const detail = detailParts.length > 0 ? detailParts.join(' · ') : null
      const enemyId = combatEnemyId(action)
      const enemyTitle = enemyId ? enemyNames.get(enemyId) : null
      const obtainFromAction = (extra: Partial<CodexObtainSource> = {}): CodexObtainSource =>
        enemyId
          ? {
              kind: 'enemy',
              title: enemyTitle ?? action['Display Name'],
              enemyId,
              locations: locs,
              ...extra,
            }
          : {
              kind: 'action',
              title: action['Display Name'],
              detail,
              actionId: action['Action ID'],
              locations: locs,
              ...extra,
            }

      if (action['Target Type'] === 'Item' && action['Target ID']) {
        addObtain(action['Target ID'], obtainFromAction())
      }

      // Gathering, combat, and other action reward tables (including secondary combat loot).
      for (const table of actionTables(action)) {
        for (const drop of tableItems.get(table.id) ?? []) {
          addObtain(
            drop.itemId,
            obtainFromAction({
              dropChance: table.chance,
              minQuantity: drop.minQuantity,
              maxQuantity: drop.maxQuantity,
            }),
          )
        }
      }
    }

    for (const recipe of this.db.Recipes) {
      const outputId = recipe['Output Item ID']
      if (!outputId.startsWith('ITEM-')) continue
      addCraft({
        id: recipe['Recipe ID'],
        isProject: false,
        displayName: recipe['Display Name'],
        skillId: recipe['Skill ID'],
        skillName: skills.get(recipe['Skill ID']) ?? recipe['Skill ID'],
        level: recipe['Proficiency Level'],
        facilityName: facilities.get(recipe['Facility ID'])?.['Display Name'] ?? null,
        output: {
          itemId: outputId,
          displayName: names.get(outputId) ?? outputId,
          minQuantity: recipe['Output Quantity'],
          maxQuantity: recipe['Output Quantity'],
        },
        ingredients: recipeIngredients(recipe).map((ingredient) => ({
          itemId: ingredient.itemId,
          displayName: names.get(ingredient.itemId) ?? ingredient.itemId,
          minQuantity: ingredient.quantity,
          maxQuantity: ingredient.quantity,
        })),
      })
    }

    for (const project of this.db.Projects) {
      const outputId = project['Output Item / Target ID']
      if (!outputId.startsWith('ITEM-')) continue
      addCraft({
        id: project['Project ID'],
        isProject: true,
        displayName: project['Display Name'],
        skillId: project['Skill ID'],
        skillName: skills.get(project['Skill ID']) ?? project['Skill ID'],
        level: project['Required Skill 1 Level'],
        facilityName: facilities.get(project['Facility ID'])?.['Display Name'] ?? null,
        output: {
          itemId: outputId,
          displayName: names.get(outputId) ?? outputId,
          minQuantity: project['Output Quantity'],
          maxQuantity: project['Output Quantity'],
        },
        ingredients: projectInputs(project).map((input) => ({
          itemId: input.itemId,
          displayName: names.get(input.itemId) ?? input.itemId,
          minQuantity: input.quantity,
          maxQuantity: input.quantity,
        })),
      })
    }

    for (const shop of this.db.Shops) {
      for (const stock of shopStockEntries(shop)) {
        const locationName = locations.get(shop['Location ID'])
        addObtain(stock.itemId, {
          kind: 'shop',
          title: shop['Display Name'],
          shopId: shop['Shop ID'],
          locations: locationName
            ? [{ locationId: shop['Location ID'], displayName: locationName }]
            : [],
        })
      }
    }

    // Quest rewards: non-cosmetic gear/tools only (see includeQuestRewardAsObtainSource).
    const itemCategory = new Map(this.db.Items.map((item) => [item['Item ID'], item.Category]))
    for (const quest of this.db.Quests) {
      const rewardId = typeof quest['Reward Item ID'] === 'string' ? quest['Reward Item ID'] : null
      if (!rewardId) continue
      if (!includeQuestRewardAsObtainSource(itemCategory.get(rewardId), rewardId)) continue
      const qty = typeof quest['Reward Item Quantity'] === 'number' ? quest['Reward Item Quantity'] : null
      const title =
        typeof quest['Display Name'] === 'string' ? quest['Display Name'] : String(quest['Quest ID'] ?? 'Quest')
      const questId = typeof quest['Quest ID'] === 'string' ? quest['Quest ID'] : null
      addObtain(rewardId, {
        kind: 'quest',
        title,
        questId,
        locations: [],
        minQuantity: qty,
        maxQuantity: qty,
      })
    }

    for (const starter of this.db.RaceStartingItems) {
      const race = this.db.Races.find((row) => row['Race ID'] === starter['Race ID'])
      addObtain(starter['Item ID'], {
        kind: 'starter',
        title: race ? `${race['Display Name']} starting kit` : 'Starting kit',
        locations: [],
        minQuantity: starter.Quantity,
        maxQuantity: starter.Quantity,
      })
    }

    const itemIds = this.db.Items.map((item) => item['Item ID'])
    itemIds.sort((a, b) => this.sorter.compareGrouped({ itemId: a }, { itemId: b }))
    for (const itemId of itemIds) {
      const item = this.db.Items.find((row) => row['Item ID'] === itemId)!
      const group = this.sorter.groupOf(itemId)
      if (includeInCodexCatalog(item)) this.itemOrder.push(itemId)
      this.itemsById.set(itemId, {
        itemId,
        displayName: item['Display Name'],
        category: item.Category,
        subtype: item.Subtype,
        description: item.Description,
        group,
        groupLabel: inventoryGroupLabel(group),
        statLines: [
          ...equipmentTooltipStatLines(equipmentForItemId(this.db, itemId), this.db),
          ...(isSpellItem(this.db, itemId) ? spellTooltipLines(this.db, item, itemId) : []),
        ],
        obtainedFrom: obtained.get(itemId) ?? [],
        craftedBy: craftedBy.get(itemId) ?? [],
        usedIn: usedIn.get(itemId) ?? [],
      })
    }

    const fishingEnemyIds = new Set<string>()
    for (const enemy of this.db.Enemies) {
      const notes = typeof enemy.Notes === 'string' ? enemy.Notes : ''
      if (/damage_mode:fishing/i.test(notes)) {
        fishingEnemyIds.add(enemy['Enemy ID'])
        const squidling = notes.match(/squidling_enemy:([A-Z0-9-]+)/i)?.[1]
        if (squidling) fishingEnemyIds.add(squidling)
      }
      if (/squidling/i.test(enemy['Display Name']) || /squidling/i.test(notes)) {
        fishingEnemyIds.add(enemy['Enemy ID'])
      }
    }

    const enemies = [...this.db.Enemies]
    enemies.sort((a, b) => {
      const level = (a['Combat Level'] ?? 0) - (b['Combat Level'] ?? 0)
      if (level !== 0) return level
      return a['Display Name'].toLowerCase().localeCompare(b['Display Name'].toLowerCase())
    })
    for (const enemy of enemies) {
      const tableId = enemy['Reward Table ID']
      const drops = (tableId ? (tableItems.get(tableId) ?? []) : []).filter(
        (drop) => drop.itemId !== GOLDEN_SPUD_ITEM_ID && this.itemsById.has(drop.itemId),
      )
      const catalogDrops = drops.filter((drop) => {
        const item = this.itemsById.get(drop.itemId)
        return item ? includeInCodexCatalog(item) : false
      })
      this.enemyOrder.push(enemy['Enemy ID'])
      this.enemiesById.set(enemy['Enemy ID'], {
        enemyId: enemy['Enemy ID'],
        displayName: enemy['Display Name'],
        combatLevel: enemy['Combat Level'],
        maximumHp: enemy['Maximum HP'],
        minDamage: enemy['Min Damage'],
        maxDamage: enemy['Max Damage'],
        combatXp: enemy['Combat XP'],
        xpSkillLabel: fishingEnemyIds.has(enemy['Enemy ID']) ? 'Fishing' : 'Might',
        minimumGold: enemy['Minimum Gold'],
        maximumGold: enemy['Maximum Gold'],
        dropChance: enemy['Drop Chance'],
        locations: this.enemyLocations(enemy, actionLocations, locations),
        drops: withDropRates(catalogDrops),
      })
    }

    const actions = this.db.Actions.filter((action) => {
      if (action.Category !== 'Gathering') return false
      if (hideActionFromCodex(action)) return false
      return true
    })
    actions.sort((a, b) => {
      const skillA = a['Relevant Skill ID'] ?? ''
      const skillB = b['Relevant Skill ID'] ?? ''
      if (skillA !== skillB) return skillA.localeCompare(skillB)
      const level = (a['Proficiency Level'] ?? 0) - (b['Proficiency Level'] ?? 0)
      if (level !== 0) return level
      return a['Display Name'].toLowerCase().localeCompare(b['Display Name'].toLowerCase())
    })
    for (const action of actions) {
      const tables = catalogActionTables(action, tableItems, this.itemsById)
      const targetId =
        action['Target Type'] === 'Item' && action['Target ID'] ? action['Target ID'] : null
      const targetItem = targetId ? this.itemsById.get(targetId) : undefined
      this.actionOrder.push(action['Action ID'])
      this.actionsById.set(action['Action ID'], {
        actionId: action['Action ID'],
        displayName: action['Display Name'],
        category: action.Category,
        skillId: action['Relevant Skill ID'],
        skillName: skills.get(action['Relevant Skill ID']) ?? null,
        level: action['Proficiency Level'],
        locations: actionLocations.get(action['Action ID']) ?? [],
        target:
          targetId && targetItem && includeInCodexCatalog(targetItem)
            ? { itemId: targetId, displayName: targetItem.displayName }
            : null,
        tables,
      })
    }
  }

  private actionLocations(locations: Map<string, string>): Map<string, CodexLocationRef[]> {
    const poolActions = new Map<string, string[]>()
    for (const entry of this.db.PoolEntries) {
      const list = poolActions.get(entry['Pool ID']) ?? []
      list.push(entry['Action ID'])
      poolActions.set(entry['Pool ID'], list)
    }
    const out = new Map<string, CodexLocationRef[]>()
    for (const activity of this.db.Activities) {
      const poolId = activity['Pool ID']
      if (!poolId) continue
      const locationName = locations.get(activity['Location ID'])
      if (!locationName) continue
      const loc = { locationId: activity['Location ID'], displayName: locationName }
      for (const actionId of poolActions.get(poolId) ?? []) {
        const list = out.get(actionId) ?? []
        if (!list.some((row) => row.locationId === loc.locationId)) list.push(loc)
        out.set(actionId, list)
      }
    }
    return out
  }

  private rewardItems(names: Map<string, string>): Map<string, CodexItemRef[]> {
    const out = new Map<string, CodexItemRef[]>()
    for (const entry of this.db.RewardEntries) {
      if (entry['Reward Type'] !== 'Item') continue
      const itemId = entry['Reward ID / Value']
      if (!itemId || !names.has(itemId)) continue
      const list = out.get(entry['Reward Table ID']) ?? []
      const existing = list.findIndex((row) => row.itemId === itemId)
      if (existing >= 0) {
        const current = list[existing]!
        list[existing] = {
          itemId,
          displayName: names.get(itemId)!,
          minQuantity: minNum(current.minQuantity, entry['Minimum Quantity']),
          maxQuantity: maxNum(current.maxQuantity, entry['Maximum Quantity']),
          weight: (current.weight ?? 0) + (entry.Weight ?? 0),
        }
      } else {
        list.push({
          itemId,
          displayName: names.get(itemId)!,
          minQuantity: entry['Minimum Quantity'],
          maxQuantity: entry['Maximum Quantity'],
          weight: entry.Weight,
        })
      }
      out.set(entry['Reward Table ID'], list)
    }
    return out
  }

  private enemyLocations(
    enemy: EnemyRow,
    actionLocations: Map<string, CodexLocationRef[]>,
    locations: Map<string, string>,
  ): CodexLocationRef[] {
    const seen = new Set<string>()
    const out: CodexLocationRef[] = []
    const add = (loc: CodexLocationRef) => {
      if (seen.has(loc.locationId)) return
      seen.add(loc.locationId)
      out.push(loc)
    }
    for (const action of this.db.Actions) {
      if (action.Category !== 'Combat' || action['Target ID'] !== enemy['Enemy ID']) continue
      for (const loc of actionLocations.get(action['Action ID']) ?? []) add(loc)
    }
    const homeId = enemy['Location ID']
    if (homeId && locations.has(homeId)) {
      add({ locationId: homeId, displayName: locations.get(homeId)! })
    }
    return out
  }
}

function actionTables(
  action: ActionRow,
): Array<{ id: string; chance: number | null; label: 'Primary' | 'Secondary' | 'Tertiary' }> {
  const out: Array<{
    id: string
    chance: number | null
    label: 'Primary' | 'Secondary' | 'Tertiary'
  }> = []
  if (action['Reward Table ID']) {
    out.push({
      id: action['Reward Table ID'],
      chance: action['Drop Chance'],
      label: 'Primary',
    })
  }
  if (action['Secondary Reward Table ID']) {
    out.push({
      id: action['Secondary Reward Table ID'],
      chance: action['Secondary Drop Chance'],
      label: 'Secondary',
    })
  }
  if (action['Tertiary Reward Table ID']) {
    out.push({
      id: action['Tertiary Reward Table ID'],
      chance: action['Tertiary Drop Chance'],
      label: 'Tertiary',
    })
  }
  return out
}

function isOreGemTable(action: ActionRow, tableId: string): boolean {
  return action['Relevant Skill ID'] === MINING_SKILL_ID && ORE_GEM_TABLE_IDS.has(tableId)
}

function catalogActionTables(
  action: ActionRow,
  tableItems: Map<string, CodexItemRef[]>,
  itemsById: Map<string, CodexItemEntry>,
): CodexActionDropTable[] {
  const keepDrop = (drop: CodexItemRef): boolean => {
    if (drop.itemId === GOLDEN_SPUD_ITEM_ID) return false
    const item = itemsById.get(drop.itemId)
    return item ? includeInCodexCatalog(item) : false
  }
  const merged: CodexItemRef[] = []
  const gems: CodexActionDropTable[] = []
  let mergedTableId: string | null = null
  for (const table of actionTables(action)) {
    const drops = (tableItems.get(table.id) ?? []).filter(keepDrop)
    if (drops.length === 0) continue
    if (isOreGemTable(action, table.id)) {
      gems.push({
        label: 'Gems',
        tableId: table.id,
        dropChance: table.chance,
        drops: withEffectiveDropRates(drops, table.chance),
      })
      continue
    }
    if (!mergedTableId) mergedTableId = table.id
    merged.push(...withEffectiveDropRates(drops, table.chance))
  }
  const out: CodexActionDropTable[] = []
  if (merged.length > 0 && mergedTableId) {
    out.push({
      label: 'Drops',
      tableId: mergedTableId,
      dropChance: null,
      drops: merged,
    })
  }
  out.push(...gems)
  return out
}

function withEffectiveDropRates(drops: CodexItemRef[], tableChance: number | null): CodexItemRef[] {
  const totalWeight = drops.reduce((sum, drop) => sum + (drop.weight ?? 0), 0)
  const chance = tableChance ?? 100
  return drops.map((drop) => ({
    ...drop,
    dropRatePercent:
      drop.weight != null && totalWeight > 0 ? (drop.weight / totalWeight) * chance : null,
  }))
}

function withDropRates(drops: CodexItemRef[]): CodexItemRef[] {
  const totalWeight = drops.reduce((sum, drop) => sum + (drop.weight ?? 0), 0)
  return drops.map((drop) => ({
    ...drop,
    dropRatePercent:
      drop.weight != null && totalWeight > 0 ? (drop.weight / totalWeight) * 100 : null,
  }))
}

function minNum(left: number | null | undefined, right: number | null | undefined): number | null {
  if (left == null) return right ?? null
  if (right == null) return left
  return left < right ? left : right
}

function maxNum(left: number | null | undefined, right: number | null | undefined): number | null {
  if (left == null) return right ?? null
  if (right == null) return left
  return left > right ? left : right
}
