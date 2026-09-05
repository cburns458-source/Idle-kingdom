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
export type CodexObtainKind = 'action' | 'enemyDrop' | 'shop' | 'quest' | 'starter'

export interface CodexItemRef {
  itemId: string
  displayName: string
  minQuantity?: number | null
  maxQuantity?: number | null
  weight?: number | null
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
  minimumGold?: number | null
  maximumGold?: number | null
  dropChance?: number | null
  locations: CodexLocationRef[]
  drops: CodexItemRef[]
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
  private readonly itemOrder: string[] = []
  private readonly enemyOrder: string[] = []

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

  item(itemId: string): CodexItemEntry | undefined {
    return this.itemsById.get(itemId)
  }

  enemy(enemyId: string): CodexEnemyEntry | undefined {
    return this.enemiesById.get(enemyId)
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

  private build() {
    const names = new Map(this.db.Items.map((item) => [item['Item ID'], item['Display Name']]))
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

    for (const action of this.db.Actions) {
      if (action.Category === 'Standard Production') continue
      const locs = actionLocations.get(action['Action ID']) ?? []
      const skillName = skills.get(action['Relevant Skill ID'])
      const level = action['Proficiency Level']
      const detailParts = [
        skillName ? skillName : null,
        typeof level === 'number' ? `Level ${level}` : null,
      ].filter((part): part is string => !!part)
      const detail = detailParts.length > 0 ? detailParts.join(' · ') : null

      if (action['Target Type'] === 'Item' && action['Target ID']) {
        addObtain(action['Target ID'], {
          kind: 'action',
          title: action['Display Name'],
          detail,
          actionId: action['Action ID'],
          locations: locs,
        })
      }

      if (action.Category === 'Combat' && action['Target ID']) {
        for (const tableId of actionTableIds(action)) {
          for (const drop of tableItems.get(tableId) ?? []) {
            addObtain(drop.itemId, {
              kind: 'enemyDrop',
              title: this.enemyName(action['Target ID']),
              detail,
              actionId: action['Action ID'],
              enemyId: action['Target ID'],
              locations: locs,
              dropChance: action['Drop Chance'],
              minQuantity: drop.minQuantity,
              maxQuantity: drop.maxQuantity,
            })
          }
        }
      } else {
        for (const table of actionTables(action)) {
          for (const drop of tableItems.get(table.id) ?? []) {
            addObtain(drop.itemId, {
              kind: 'action',
              title: action['Display Name'],
              detail,
              actionId: action['Action ID'],
              locations: locs,
              dropChance: table.chance,
              minQuantity: drop.minQuantity,
              maxQuantity: drop.maxQuantity,
            })
          }
        }
      }
    }

    for (const enemy of this.db.Enemies) {
      const tableId = enemy['Reward Table ID']
      if (!tableId) continue
      for (const drop of tableItems.get(tableId) ?? []) {
        addObtain(drop.itemId, {
          kind: 'enemyDrop',
          title: enemy['Display Name'],
          enemyId: enemy['Enemy ID'],
          locations: this.enemyLocations(enemy, actionLocations, locations),
          dropChance: enemy['Drop Chance'],
          minQuantity: drop.minQuantity,
          maxQuantity: drop.maxQuantity,
        })
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

    for (const quest of this.db.Quests) {
      const itemId = quest['Reward Item ID']
      if (typeof itemId !== 'string' || !itemId) continue
      const qty = quest['Reward Item Quantity']
      addObtain(itemId, {
        kind: 'quest',
        title: typeof quest['Display Name'] === 'string' ? quest['Display Name'] : 'Quest',
        questId: typeof quest['Quest ID'] === 'string' ? quest['Quest ID'] : null,
        locations: [],
        minQuantity: typeof qty === 'number' ? qty : null,
        maxQuantity: typeof qty === 'number' ? qty : null,
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
      this.itemOrder.push(itemId)
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

    const enemies = [...this.db.Enemies]
    enemies.sort((a, b) => {
      const level = (a['Combat Level'] ?? 0) - (b['Combat Level'] ?? 0)
      if (level !== 0) return level
      return a['Display Name'].toLowerCase().localeCompare(b['Display Name'].toLowerCase())
    })
    for (const enemy of enemies) {
      const tableId = enemy['Reward Table ID']
      this.enemyOrder.push(enemy['Enemy ID'])
      this.enemiesById.set(enemy['Enemy ID'], {
        enemyId: enemy['Enemy ID'],
        displayName: enemy['Display Name'],
        combatLevel: enemy['Combat Level'],
        maximumHp: enemy['Maximum HP'],
        minDamage: enemy['Min Damage'],
        maxDamage: enemy['Max Damage'],
        combatXp: enemy['Combat XP'],
        minimumGold: enemy['Minimum Gold'],
        maximumGold: enemy['Maximum Gold'],
        dropChance: enemy['Drop Chance'],
        locations: this.enemyLocations(enemy, actionLocations, locations),
        drops: tableId ? (tableItems.get(tableId) ?? []) : [],
      })
    }
  }

  private enemyName(enemyId: string): string {
    return this.db.Enemies.find((row) => row['Enemy ID'] === enemyId)?.['Display Name'] ?? enemyId
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

function actionTableIds(action: ActionRow): string[] {
  return actionTables(action).map((table) => table.id)
}

function actionTables(action: ActionRow): Array<{ id: string; chance: number | null }> {
  const out: Array<{ id: string; chance: number | null }> = []
  if (action['Reward Table ID']) {
    out.push({ id: action['Reward Table ID'], chance: action['Drop Chance'] })
  }
  if (action['Secondary Reward Table ID']) {
    out.push({ id: action['Secondary Reward Table ID'], chance: action['Secondary Drop Chance'] })
  }
  if (action['Tertiary Reward Table ID']) {
    out.push({ id: action['Tertiary Reward Table ID'], chance: action['Tertiary Drop Chance'] })
  }
  return out
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
