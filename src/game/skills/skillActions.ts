import type { ActionRow, GameDatabase, ItemRow, RequirementRow } from '../data/types'
import type { ProjectRow } from '../data/projectTypes'
import { requirementsForEntity } from '../activity/requirements'
import { MIGHT_SKILL_ID, VITALITY_SKILL_ID } from '../combat/stats'
import { ARTISANRY_SKILL_ID, ARCANA_SKILL_ID, SMITHING_SKILL_ID } from '../npcs/knowledge'
import { isCompleteRecipe } from '../production/recipes'
import {
  getEnchantment,
  isCompleteProject,
  isEnchantmentOutput,
  projectSkillRequirements,
} from '../projects/projects'
import {
  botanyPlantDisplayName,
  FISHING_POT_ITEM_ID,
  POT_FISH_BY_LOCATION,
} from '../timers/locationTimers'

export const ESSENCE_ITEM_ID = 'ITEM-0011'
export const MINING_SKILL_ID = 'SKL-0002'
export const FISHING_SKILL_ID = 'SKL-0003'
export const HARVESTING_SKILL_ID = 'SKL-0004'
export const HUNTING_SKILL_ID = 'SKL-0005'
export const WOODCUTTING_SKILL_ID = 'SKL-0006'
export const COOKING_SKILL_ID = 'SKL-0007'
export const BOTANY_SKILL_ID = 'SKL-0014'
export const THIEVERY_SKILL_ID = 'SKL-0015'

const WOODEN_MINING_TOOLS = ['ITEM-0102']
const WOODEN_WOODCUTTING_TOOLS = ['ITEM-0100', 'ITEM-0101']
const WOODEN_FISHING_TOOLS = ['ITEM-0103']
const WOODEN_HUNTING_TOOLS = ['ITEM-0108', 'ITEM-0109']
const WOODEN_COMBAT_GEAR = ['ITEM-0124', 'ITEM-0125', 'ITEM-0145']

const COMBAT_GEAR_WORDS = [
  'Sword',
  'Dagger',
  'Shield',
  'Helmet',
  'Chestplate',
  'Platelegs',
  'Boots',
  'Gloves',
  'Warhammer',
  'Battleaxe',
  'Bow',
  'Spear',
] as const

const COMBAT_ARMOR_WORDS = ['Helmet', 'Chestplate', 'Platelegs', 'Boots', 'Gloves', 'Shield'] as const
const COMBAT_WEAPON_WORDS = ['Sword', 'Dagger', 'Warhammer', 'Battleaxe'] as const

export interface SkillMenuListItem {
  id: string
  displayName: string
  level: number | null
}

export interface SkillMenuSection {
  title: string | null
  entries: SkillMenuListItem[]
}

export interface SkillMenuTab {
  id: string
  label: string
  sections: SkillMenuSection[]
}

export interface SkillMenuView {
  skillId: string
  tabs: SkillMenuTab[]
  showRecipeBook: boolean
}

export function activitiesForAction(db: GameDatabase, actionId: string): GameDatabase['Activities'] {
  const poolIds = new Set(
    db.PoolEntries.filter((entry) => entry['Action ID'] === actionId).map((entry) => entry['Pool ID']),
  )
  if (poolIds.size === 0) return []
  return db.Activities.filter((activity) => {
    const poolId = activity['Pool ID']
    return poolId != null && poolIds.has(poolId)
  })
}

function isQuestOnlyRequirement(requirement: RequirementRow): boolean {
  const type = requirement['Requirement Type']
  return (
    type === 'Quest Access' ||
    type === 'Quest Flag' ||
    type === 'Quest Active' ||
    type === 'Quest Complete'
  )
}

/** True when every activity that can roll this action is quest-gated. */
export function actionIsQuestOnly(db: GameDatabase, actionId: string): boolean {
  const activities = activitiesForAction(db, actionId)
  if (activities.length === 0) return false
  return activities.every((activity) =>
    requirementsForEntity(db, 'Activity', activity['Activity ID']).some(isQuestOnlyRequirement),
  )
}

/** Gathering skill menus list world actions, not boss/combat rows tagged to the skill. */
function isGatheringSkillMenuAction(action: ActionRow): boolean {
  return action.Category !== 'Combat'
}

function thieveryActionNotes(action: ActionRow): string {
  return action.Notes ?? ''
}

/** Lockpick / safe / deposit-box thievery (RequiresLockpick family). */
export function isThieveryLockpickAction(action: ActionRow): boolean {
  const notes = thieveryActionNotes(action)
  return (
    /RequiresLockpick/i.test(notes) ||
    /ThieveryLockpick/i.test(notes) ||
    /BankThievery/i.test(notes)
  )
}

/** Shop-style steals, including Steal from goblins. */
export function isThieveryShopAction(action: ActionRow): boolean {
  if (action['Relevant Skill ID'] !== THIEVERY_SKILL_ID) return false
  if (isThieveryLockpickAction(action)) return false
  return /ThieverySteal/i.test(thieveryActionNotes(action)) || action.Category === 'Gathering'
}

/** Actions for a skill menu: display names only, unique by name, proficiency when set. */
export function actionsForSkill(db: GameDatabase, skillId: string): SkillMenuListItem[] {
  const rows = db.Actions.filter(
    (action) =>
      action['Relevant Skill ID'] === skillId &&
      action.Status !== 'Needs Data' &&
      Boolean(action['Display Name']?.trim()) &&
      !actionIsQuestOnly(db, action['Action ID']),
  )

  rows.sort(compareSkillActions)

  const seen = new Set<string>()
  const items: SkillMenuListItem[] = []
  for (const action of rows) {
    const displayName = action['Display Name']!.trim()
    if (seen.has(displayName)) continue
    seen.add(displayName)
    const proficiency = action['Proficiency Level']
    items.push({
      id: action['Action ID'],
      displayName,
      level: typeof proficiency === 'number' ? proficiency : null,
    })
  }
  return items
}

/** Projects for smithing / artisanry / arcana: resulting item name + required level. */
export function projectsForSkill(db: GameDatabase, skillId: string): SkillMenuListItem[] {
  const rows = db.Projects.filter(
    (project) => project['Skill ID'] === skillId && isCompleteProject(project),
  )

  rows.sort((a, b) => {
    const aLevel = projectLevelForSkill(a, skillId) ?? Number.POSITIVE_INFINITY
    const bLevel = projectLevelForSkill(b, skillId) ?? Number.POSITIVE_INFINITY
    if (aLevel !== bLevel) return aLevel - bLevel
    return projectOutputName(db, a).localeCompare(projectOutputName(db, b))
  })

  const seen = new Set<string>()
  const items: SkillMenuListItem[] = []
  for (const project of rows) {
    const displayName = projectOutputName(db, project)
    if (!displayName || seen.has(displayName)) continue
    seen.add(displayName)
    items.push({
      id: project['Project ID'],
      displayName,
      level: projectLevelForSkill(project, skillId),
    })
  }
  return items
}

/** Combined skill menu rows: actions first, then projects. */
export function skillMenuEntries(db: GameDatabase, skillId: string): SkillMenuListItem[] {
  return [...actionsForSkill(db, skillId), ...projectsForSkill(db, skillId)]
}

/** `{level}. {name}` for a skill-menu row. */
export function skillMenuLine(item: SkillMenuListItem): string {
  if (item.level == null) return item.displayName
  const number = Number.isInteger(item.level) ? item.level : item.level
  return `${number}. ${item.displayName}`
}

/** Tabbed catalog for a skill tile. */
export function skillMenuView(db: GameDatabase, skillId: string): SkillMenuView {
  const tabs = nonEmptyTabs(tabsForSkill(db, skillId))
  return {
    skillId,
    tabs: tabs.length === 0 ? [listTab('actions', 'Actions', [])] : tabs,
    showRecipeBook: skillHasRecipeBook(db, skillId),
  }
}

/** Flattened tabs, used by older tests and parity. */
export function skillMenuDisplayEntries(db: GameDatabase, skillId: string): SkillMenuListItem[] {
  return skillMenuView(db, skillId).tabs.flatMap((tab) =>
    tab.sections.flatMap((section) => section.entries),
  )
}

/** Whether this skill has production recipes or projects to put in a book. */
export function skillHasRecipeBook(db: GameDatabase, skillId: string): boolean {
  return (
    db.Recipes.some((recipe) => recipe['Skill ID'] === skillId && isCompleteRecipe(recipe)) ||
    db.Projects.some((project) => project['Skill ID'] === skillId && isCompleteProject(project))
  )
}

export interface SkillMenuPlacement {
  tabId: string
  tabLabel: string
  sectionTitle: string | null
}

/** Where a named output belongs in the skill menu / recipe book. */
export function skillMenuPlacementForOutput(
  db: GameDatabase,
  skillId: string,
  displayName: string,
  outputId = '',
): SkillMenuPlacement {
  if (skillId === SMITHING_SKILL_ID) {
    const material = smithingMaterial(displayName)
    if (material) {
      return { tabId: 'basic-metal', tabLabel: 'Basic metal', sectionTitle: `${material} items` }
    }
    return { tabId: 'other', tabLabel: 'Other', sectionTitle: null }
  }
  if (skillId === ARTISANRY_SKILL_ID) {
    if (isBowName(displayName)) return { tabId: 'bows', tabLabel: 'Bows', sectionTitle: null }
    const item = outputId
      ? db.Items.find((row) => row['Item ID'] === outputId)
      : itemByName(db, displayName)
    if (isJewelryItem(item, displayName)) {
      return { tabId: 'jewelry', tabLabel: 'Jewelry', sectionTitle: null }
    }
    const material = armorMaterial(displayName)
    if (material && isGroupedArmorMaterial(material)) {
      return { tabId: 'other', tabLabel: 'Other', sectionTitle: `${material} equipment` }
    }
    return { tabId: 'other', tabLabel: 'Other', sectionTitle: null }
  }
  if (skillId === ARCANA_SKILL_ID) {
    if (outputId === ESSENCE_ITEM_ID || displayName === 'Essence') {
      return { tabId: 'essence', tabLabel: 'Essence', sectionTitle: null }
    }
    if (isSpellName(displayName)) return { tabId: 'spells', tabLabel: 'Spells', sectionTitle: null }
    if (isArcanaWeaponName(displayName, outputId)) {
      return { tabId: 'equipment', tabLabel: 'Equipment', sectionTitle: null }
    }
    return { tabId: 'enchants', tabLabel: 'Enchants', sectionTitle: null }
  }
  if (skillId === THIEVERY_SKILL_ID) {
    const action =
      (outputId
        ? db.Actions.find((row) => row['Action ID'] === outputId)
        : undefined) ?? db.Actions.find((row) => row['Display Name'] === displayName)
    if (action && isThieveryLockpickAction(action)) {
      return { tabId: 'lockpicking', tabLabel: 'Lockpicking', sectionTitle: null }
    }
    return { tabId: 'shops', tabLabel: 'Shops', sectionTitle: null }
  }
  if (skillId === COOKING_SKILL_ID) return cookingPlacement(displayName)
  if (skillMenuView(db, skillId).tabs.some((tab) => tab.id === 'actions')) {
    return { tabId: 'actions', tabLabel: 'Actions', sectionTitle: null }
  }
  const first = skillMenuView(db, skillId).tabs[0]!
  return { tabId: first.id, tabLabel: first.label, sectionTitle: null }
}

export function projectOutputName(db: GameDatabase, project: ProjectRow): string {
  const outputId = project['Output Item / Target ID']
  if (!outputId) return project['Display Name']
  if (isEnchantmentOutput(outputId)) {
    return getEnchantment(db, outputId)?.['Display Name'] ?? project['Display Name']
  }
  return (
    db.Items.find((item) => item['Item ID'] === outputId)?.['Display Name'] ??
    project['Display Name']
  )
}

function tabsForSkill(db: GameDatabase, skillId: string): SkillMenuTab[] {
  if (skillId === MIGHT_SKILL_ID) {
    return [
      listTab('weapons', 'Weapons', combatWeaponEntries(db)),
      listTab('other', 'Other', combatOtherWeaponEntries(db)),
    ]
  }
  if (skillId === VITALITY_SKILL_ID) {
    return [
      listTab('gear', 'Equipment', combatEquipmentEntries(db)),
      listTab('other', 'Other', combatOtherEquipmentEntries(db)),
    ]
  }
  if (skillId === FISHING_SKILL_ID) return fishingTabs(db)
  if (skillId === COOKING_SKILL_ID) return cookingTabs(db)
  if (
    skillId === MINING_SKILL_ID ||
    skillId === HARVESTING_SKILL_ID ||
    skillId === HUNTING_SKILL_ID ||
    skillId === WOODCUTTING_SKILL_ID
  ) {
    return [
      listTab('actions', 'Actions', gatheringSkillActions(db, skillId)),
      listTab('tools', 'Tools', gatheringToolEntries(db, skillId)),
    ]
  }
  if (skillId === BOTANY_SKILL_ID) return botanyTabs(db)
  if (skillId === THIEVERY_SKILL_ID) return thieveryTabs(db)
  if (skillId === SMITHING_SKILL_ID) return smithingTabs(db)
  if (skillId === ARTISANRY_SKILL_ID) return artisanryTabs(db)
  if (skillId === ARCANA_SKILL_ID) return arcanaTabs(db)
  return [listTab('actions', 'Actions', skillMenuEntries(db, skillId))]
}

function gatheringSkillActions(db: GameDatabase, skillId: string): SkillMenuListItem[] {
  return actionsForSkill(db, skillId).filter((item) => {
    const action = db.Actions.find((row) => row['Action ID'] === item.id)
    return action != null && isGatheringSkillMenuAction(action)
  })
}

function thieveryTabs(db: GameDatabase): SkillMenuTab[] {
  const shops: SkillMenuListItem[] = []
  const lockpicking: SkillMenuListItem[] = []
  for (const item of actionsForSkill(db, THIEVERY_SKILL_ID)) {
    const action = db.Actions.find((row) => row['Action ID'] === item.id)
    if (!action) continue
    if (isThieveryLockpickAction(action)) lockpicking.push(item)
    else if (isThieveryShopAction(action)) shops.push(item)
  }
  return [listTab('shops', 'Shops', shops), listTab('lockpicking', 'Lockpicking', lockpicking)]
}

const BOTANY_CROP_SEED_IDS = new Set([
  'ITEM-0324',
  'ITEM-0339',
  'ITEM-0369',
  'ITEM-0340',
  'ITEM-0371',
])
const BOTANY_HERB_SEED_IDS = new Set([
  'ITEM-0333',
  'ITEM-0334',
  'ITEM-0336',
  'ITEM-0373',
  'ITEM-0350',
])
const BOTANY_FLOWER_SEED_IDS = new Set(['ITEM-0337', 'ITEM-0375'])

function botanyTabIdForPlant(itemId: string, tags: string): string {
  if (BOTANY_CROP_SEED_IDS.has(itemId)) return 'crops'
  if (BOTANY_HERB_SEED_IDS.has(itemId)) return 'herbs'
  if (BOTANY_FLOWER_SEED_IDS.has(itemId)) return 'flowers'
  if (tags.includes('botany_sapling')) return 'trees'
  return 'fruit_trees'
}

function botanyTabs(db: GameDatabase): SkillMenuTab[] {
  const buckets: Record<string, SkillMenuListItem[]> = {
    flowers: [],
    crops: [],
    herbs: [],
    trees: [],
    fruit_trees: [],
  }
  for (const item of db.Items) {
    if (item.Status !== 'Confirmed' && item.Status !== 'Planned') continue
    if (item['Release Phase'] !== 'Launch') continue
    const tags = (item['Functional / Source Tags'] ?? '').toLowerCase()
    if (!tags.includes('botany_seed') && !tags.includes('botany_sapling')) continue
    const notes = item.Notes ?? ''
    const level = Number(/RequiresLevel:(\d+)/i.exec(notes)?.[1] ?? 1)
    const entry: SkillMenuListItem = {
      id: item['Item ID'],
      displayName: botanyPlantDisplayName(item['Display Name']),
      level: level < 1 ? 1 : level,
    }
    const tabId = botanyTabIdForPlant(item['Item ID'], tags)
    ;(buckets[tabId] ?? buckets.fruit_trees)!.push(entry)
  }
  for (const entries of Object.values(buckets)) {
    entries.sort((a, b) => {
      const level = (a.level ?? 0) - (b.level ?? 0)
      if (level !== 0) return level
      return a.displayName.localeCompare(b.displayName)
    })
  }
  return [
    listTab('crops', 'Crops', buckets.crops ?? []),
    listTab('herbs', 'Herbs', buckets.herbs ?? []),
    listTab('flowers', 'Flowers', buckets.flowers ?? []),
    listTab('trees', 'Trees', buckets.trees ?? []),
    listTab('fruit_trees', 'Fruit trees', buckets.fruit_trees ?? []),
  ]
}

function potFishingEntries(db: GameDatabase): SkillMenuListItem[] {
  const entries: SkillMenuListItem[] = []
  const seen = new Set<string>()
  for (const table of Object.values(POT_FISH_BY_LOCATION)) {
    for (const row of table) {
      if (seen.has(row.itemId)) continue
      seen.add(row.itemId)
      const item = db.Items.find((entry) => entry['Item ID'] === row.itemId)
      if (!item) continue
      entries.push({
        id: item['Item ID'],
        displayName: item['Display Name'],
        level: row.fishingLevel,
      })
    }
  }
  entries.sort(compareMenuItems)
  return entries
}

function fishingTabs(db: GameDatabase): SkillMenuTab[] {
  return [
    listTab('actions', 'Actions', gatheringSkillActions(db, FISHING_SKILL_ID)),
    listTab('tools', 'Tools', gatheringToolEntries(db, FISHING_SKILL_ID)),
    listTab('pot_fishing', 'Pot fishing', potFishingEntries(db)),
  ]
}

const COOKING_FISH_NAMES = [
  'perch',
  'trout',
  'salmon',
  'tuna',
  'shark',
  'squid',
  'catfish',
  'crawfish',
  'crab',
  'lobster',
  'eel',
]

const COOKING_MEAT_NAMES = ['rabbit', 'pheasant', 'beef', 'venison']

function cookingTabId(displayName: string): 'fish' | 'meat' | 'stew' | 'other' {
  const lower = displayName.toLowerCase()
  if (lower.includes('stew') || lower.includes('soup')) return 'stew'
  if (COOKING_FISH_NAMES.some((name) => lower.includes(name))) return 'fish'
  if (COOKING_MEAT_NAMES.some((name) => lower.includes(name))) return 'meat'
  return 'other'
}

function cookingPlacement(displayName: string): SkillMenuPlacement {
  const tabId = cookingTabId(displayName)
  const labels = { fish: 'Fish', meat: 'Meat', stew: 'Stew', other: 'Other' } as const
  return { tabId, tabLabel: labels[tabId], sectionTitle: null }
}

function cookingTabs(db: GameDatabase): SkillMenuTab[] {
  const fish: SkillMenuListItem[] = []
  const meat: SkillMenuListItem[] = []
  const stew: SkillMenuListItem[] = []
  const other: SkillMenuListItem[] = []
  for (const item of skillMenuEntries(db, COOKING_SKILL_ID)) {
    switch (cookingTabId(item.displayName)) {
      case 'fish':
        fish.push(item)
        break
      case 'meat':
        meat.push(item)
        break
      case 'stew':
        stew.push(item)
        break
      default:
        other.push(item)
    }
  }
  return [
    listTab('fish', 'Fish', fish),
    listTab('meat', 'Meat', meat),
    listTab('stew', 'Stew', stew),
    listTab('other', 'Other', other),
  ]
}

function smithingTabs(db: GameDatabase): SkillMenuTab[] {
  const grouped: SkillMenuListItem[] = []
  const other: SkillMenuListItem[] = []
  const seenMaterials = new Set<string>()
  for (const project of projectsForSkill(db, SMITHING_SKILL_ID)) {
    const material = smithingMaterial(project.displayName)
    if (!material) {
      other.push(project)
      continue
    }
    const key = `${project.level ?? ''}|${material}`
    if (seenMaterials.has(key)) continue
    seenMaterials.add(key)
    grouped.push({
      id: key,
      displayName: `${material} items`,
      level: project.level,
    })
  }
  return [listTab('basic-metal', 'Basic metal', grouped), listTab('other', 'Other', other)]
}

function artisanryTabs(db: GameDatabase): SkillMenuTab[] {
  const bows: SkillMenuListItem[] = []
  const jewelry: SkillMenuListItem[] = []
  const other: SkillMenuListItem[] = []
  const seenLeather = new Set<string>()
  for (const project of projectsForSkill(db, ARTISANRY_SKILL_ID)) {
    const item = itemByName(db, project.displayName)
    if (isBowName(project.displayName)) bows.push(project)
    else if (isJewelryItem(item, project.displayName)) jewelry.push(project)
    else {
      const material = armorMaterial(project.displayName)
      if (material && isGroupedArmorMaterial(material)) {
        const key = `${project.level ?? ''}|${material}`
        if (seenLeather.has(key)) continue
        seenLeather.add(key)
        other.push({
          id: key,
          displayName: `${material} equipment`,
          level: project.level,
        })
      } else {
        other.push(project)
      }
    }
  }
  return [
    listTab('bows', 'Bows', bows),
    listTab('jewelry', 'Jewelry', jewelry),
    listTab('other', 'Other', other),
  ]
}

function arcanaTabs(db: GameDatabase): SkillMenuTab[] {
  const spells: SkillMenuListItem[] = [...actionsForSkill(db, ARCANA_SKILL_ID)]
  const weapons: SkillMenuListItem[] = []
  const enchantments: SkillMenuListItem[] = []
  for (const project of projectsForSkill(db, ARCANA_SKILL_ID)) {
    const outputId = projectOutputId(db, project.id)
    if (isSpellName(project.displayName)) spells.push(project)
    else if (isArcanaWeaponName(project.displayName, outputId)) weapons.push(project)
    else if (isEnchantmentName(project.displayName, outputId)) enchantments.push(project)
    else enchantments.push(project)
  }
  return [
    listTab('essence', 'Essence', arcanaEssenceEntries(db)),
    listTab('spells', 'Spells', dedupeByName(spells)),
    listTab('equipment', 'Equipment', dedupeByName(weapons)),
    listTab('enchants', 'Enchants', dedupeByName(enchantments)),
  ]
}

function arcanaEssenceEntries(db: GameDatabase): SkillMenuListItem[] {
  const item = db.Items.find((row) => row['Item ID'] === ESSENCE_ITEM_ID)
  if (!item) return []
  return [{ id: item['Item ID'], displayName: item['Display Name'], level: 1 }]
}

function combatGearItems(db: GameDatabase): SkillMenuListItem[] {
  return [
    ...projectItemsWhere(db, (item) => isCombatGearItem(item), new Set([SMITHING_SKILL_ID, ARTISANRY_SKILL_ID])),
    ...woodenItems(db, WOODEN_COMBAT_GEAR),
  ]
}

function combatEquipmentEntries(db: GameDatabase): SkillMenuListItem[] {
  const grouped: SkillMenuListItem[] = []
  const seen = new Set<string>()
  for (const item of combatGearItems(db)) {
    const material = armorMaterial(item.displayName)
    if (!material || !isGroupedArmorMaterial(material)) continue
    const key = `${item.level ?? ''}|${material}`
    if (seen.has(key)) continue
    seen.add(key)
    grouped.push({
      id: key,
      displayName: `${material} equipment`,
      level: item.level,
    })
  }
  return dedupeByName(grouped)
}

function combatWeaponEntries(db: GameDatabase): SkillMenuListItem[] {
  const grouped: SkillMenuListItem[] = []
  const seen = new Set<string>()
  for (const item of combatGearItems(db)) {
    if (armorMaterial(item.displayName)) continue
    const material = weaponMaterial(item.displayName)
    if (!material || !isWeaponMenuMaterial(material)) continue
    const key = `${item.level ?? ''}|${material}`
    if (seen.has(key)) continue
    seen.add(key)
    grouped.push({
      id: key,
      displayName: `${material} weapons`,
      level: item.level,
    })
  }
  return dedupeByName(grouped)
}

function combatOtherEntries(db: GameDatabase): SkillMenuListItem[] {
  return dedupeByName(
    combatGearItems(db).filter((item) => {
      const armor = armorMaterial(item.displayName)
      if (armor) return !isGroupedArmorMaterial(armor)
      const weapon = weaponMaterial(item.displayName)
      if (weapon) return !isWeaponMenuMaterial(weapon)
      return true
    }),
  )
}

function combatOtherWeaponEntries(db: GameDatabase): SkillMenuListItem[] {
  return combatOtherEntries(db).filter((item) => !armorMaterial(item.displayName))
}

function combatOtherEquipmentEntries(db: GameDatabase): SkillMenuListItem[] {
  return combatOtherEntries(db).filter((item) => Boolean(armorMaterial(item.displayName)))
}

function gatheringToolEntries(db: GameDatabase, skillId: string): SkillMenuListItem[] {
  const spec = gatheringToolSpec(skillId)
  if (!spec) return []
  const entries = dedupeByName(
    [...projectItemsWhere(db, spec.match, null), ...woodenItems(db, spec.woodenIds)].map((item) => ({
      ...item,
      level: equipLevelForSkill(db, item.displayName, skillId) ?? item.level,
    })),
  )
  if (skillId === FISHING_SKILL_ID) {
    const pot = db.Items.find((row) => row['Item ID'] === FISHING_POT_ITEM_ID)
    if (pot && !entries.some((item) => item.displayName === pot['Display Name'])) {
      entries.push({ id: pot['Item ID'], displayName: pot['Display Name'], level: 14 })
    }
    return dedupeByName(entries)
  }
  return entries
}

function equipLevelForSkill(db: GameDatabase, displayName: string, skillId: string): number | null {
  const item = db.Items.find((row) => row['Display Name'] === displayName)
  if (!item) return null
  const equipment = db.Equipment.find((row) => row['Item ID'] === item['Item ID'])
  if (!equipment || equipment['Required Skill ID'] !== skillId) return null
  return typeof equipment['Required Level'] === 'number' ? equipment['Required Level'] : null
}

function gatheringToolSpec(
  skillId: string,
): { woodenIds: string[]; match: (item: ItemRow, name: string) => boolean } | null {
  switch (skillId) {
    case MINING_SKILL_ID:
      return { woodenIds: WOODEN_MINING_TOOLS, match: (_item, name) => endsWithWord(name, 'Pickaxe') }
    case WOODCUTTING_SKILL_ID:
      return { woodenIds: WOODEN_WOODCUTTING_TOOLS, match: (_item, name) => isWoodcuttingToolName(name) }
    case FISHING_SKILL_ID:
      return { woodenIds: WOODEN_FISHING_TOOLS, match: (_item, name) => isFishingToolName(name) }
    case HUNTING_SKILL_ID:
      return { woodenIds: WOODEN_HUNTING_TOOLS, match: (_item, name) => isHuntingToolName(name) }
    default:
      return null
  }
}

function projectItemsWhere(
  db: GameDatabase,
  match: (item: ItemRow, name: string) => boolean,
  skillIds: Set<string> | null,
): SkillMenuListItem[] {
  const items: SkillMenuListItem[] = []
  for (const project of db.Projects.filter(isCompleteProject)) {
    const projectSkillId = project['Skill ID']
    if (skillIds && !skillIds.has(projectSkillId)) continue
    const outputId = project['Output Item / Target ID'] ?? ''
    if (outputId.startsWith('ENCH-')) continue
    const item = db.Items.find((row) => row['Item ID'] === outputId)
    if (!item || !match(item, item['Display Name'])) continue
    items.push({
      id: project['Project ID'],
      displayName: item['Display Name'],
      level: projectLevelForSkill(project, projectSkillId),
    })
  }
  return items
}

function woodenItems(db: GameDatabase, itemIds: string[]): SkillMenuListItem[] {
  const items: SkillMenuListItem[] = []
  for (const itemId of itemIds) {
    const item = db.Items.find((row) => row['Item ID'] === itemId)
    if (!item) continue
    items.push({
      id: item['Item ID'],
      displayName: item['Display Name'],
      level: woodenToolLevel(db, itemId),
    })
  }
  return items
}

function woodenToolLevel(db: GameDatabase, itemId: string): number {
  const level = db.Equipment.find((row) => row['Item ID'] === itemId)?.['Required Level']
  return typeof level === 'number' ? level : 1
}

function listTab(id: string, label: string, entries: SkillMenuListItem[]): SkillMenuTab {
  return { id, label, sections: [{ title: null, entries }] }
}

function nonEmptyTabs(tabs: SkillMenuTab[]): SkillMenuTab[] {
  return tabs.filter((tab) => tab.sections.some((section) => section.entries.length > 0))
}

function dedupeByName(items: SkillMenuListItem[]): SkillMenuListItem[] {
  const copy = [...items].sort(compareMenuItems)
  const seen = new Set<string>()
  const out: SkillMenuListItem[] = []
  for (const item of copy) {
    if (seen.has(item.displayName)) continue
    seen.add(item.displayName)
    out.push(item)
  }
  return out
}

const STARTER_MATERIAL_RANK: Record<string, number> = {
  wooden: 0,
  leather: 1,
  copper: 2,
}

function starterMaterialRank(name: string): number | null {
  const first = name.trim().split(/\s+/)[0]?.toLowerCase()
  if (!first) return null
  const rank = STARTER_MATERIAL_RANK[first]
  return rank === undefined ? null : rank
}

function compareMenuItems(a: SkillMenuListItem, b: SkillMenuListItem): number {
  const aLevel = a.level ?? Number.POSITIVE_INFINITY
  const bLevel = b.level ?? Number.POSITIVE_INFINITY
  if (aLevel !== bLevel) return aLevel - bLevel
  const aRank = starterMaterialRank(a.displayName)
  const bRank = starterMaterialRank(b.displayName)
  if (aRank != null && bRank != null && aRank !== bRank) return aRank - bRank
  return a.displayName.localeCompare(b.displayName)
}

const METAL_MATERIALS = new Set([
  'copper',
  'tin',
  'bronze',
  'iron',
  'steel',
  'reinforced steel',
  'titanium',
  'tungsten',
  'silver',
  'gold',
  'mithril',
])

function isMetalMaterial(material: string): boolean {
  const lower = material.toLowerCase()
  if (METAL_MATERIALS.has(lower)) return true
  return /^(copper|tin|bronze|iron|steel|titanium|tungsten|silver|gold|mithril)/i.test(lower)
}

function isWeaponMenuMaterial(material: string): boolean {
  return isMetalMaterial(material) || material.toLowerCase() === 'wooden'
}

function isGroupedArmorMaterial(material: string): boolean {
  const lower = material.toLowerCase()
  return isMetalMaterial(material) || lower === 'leather' || lower === 'wooden'
}

function smithingMaterial(name: string): string | null {
  const parts = name.trim().split(/\s+/)
  if (parts.length < 2) return null
  return parts[0] ?? null
}

function armorMaterial(name: string): string | null {
  for (const word of COMBAT_ARMOR_WORDS) {
    if (!endsWithWord(name, word)) continue
    const material = name.slice(0, Math.max(0, name.length - word.length)).trim()
    return material || null
  }
  return null
}

function weaponMaterial(name: string): string | null {
  for (const word of COMBAT_WEAPON_WORDS) {
    if (!endsWithWord(name, word)) continue
    const material = name.slice(0, Math.max(0, name.length - word.length)).trim()
    return material || null
  }
  return null
}

function endsWithWord(name: string, word: string): boolean {
  return name === word || name.endsWith(` ${word}`)
}

function isWoodcuttingToolName(name: string): boolean {
  if (endsWithWord(name, 'Battleaxe')) return false
  return endsWithWord(name, 'Axe') || endsWithWord(name, 'Hatchet')
}

function isFishingToolName(name: string): boolean {
  return name.includes('Fishing Rod') || endsWithWord(name, 'Harpoon') || name === 'Fishing Pot'
}

function isHuntingToolName(name: string): boolean {
  return (
    endsWithWord(name, 'Bow') ||
    endsWithWord(name, 'Spear') ||
    name === 'Sling' ||
    name === 'Bola' ||
    name === 'Magic Bola'
  )
}

function isBowName(name: string): boolean {
  return endsWithWord(name, 'Bow')
}

function isJewelryItem(item: ItemRow | undefined, name: string): boolean {
  if (item?.Category === 'Jewelry') return true
  return name.includes('Necklace') || name.includes('Ring')
}

function isCombatGearItem(item: ItemRow): boolean {
  if (item.Category === 'Tool' || item.Category === 'Jewelry') return false
  const name = item['Display Name']
  if (name.includes('Necklace') || name.includes('Ring') || name.includes('Backpack')) return false
  if (isWoodcuttingToolName(name) || endsWithWord(name, 'Pickaxe') || isFishingToolName(name)) {
    return false
  }
  return COMBAT_GEAR_WORDS.some((word) => endsWithWord(name, word))
}

function isSpellName(name: string): boolean {
  return name.includes('Spell')
}

function isArcanaWeaponName(name: string, outputId: string): boolean {
  if (outputId.startsWith('ENCH-')) return false
  return (
    /staff of\b/i.test(name) ||
    /\bstaff\b/i.test(name) ||
    /\bwand\b/i.test(name) ||
    name === 'Magic Bola'
  )
}

function isEnchantmentName(name: string, outputId: string): boolean {
  return outputId.startsWith('ENCH-') || name.includes('Enchantment') || name.includes('Enchanted')
}

function itemByName(db: GameDatabase, name: string): ItemRow | undefined {
  return db.Items.find((item) => item['Display Name'] === name)
}

function projectOutputId(db: GameDatabase, projectId: string): string {
  return db.Projects.find((row) => row['Project ID'] === projectId)?.['Output Item / Target ID'] ?? ''
}

function projectLevelForSkill(project: ProjectRow, skillId: string): number | null {
  const match = projectSkillRequirements(project).find((requirement) => requirement.skillId === skillId)
  return match?.level ?? null
}

function compareSkillActions(a: ActionRow, b: ActionRow): number {
  const aProf =
    typeof a['Proficiency Level'] === 'number' ? a['Proficiency Level'] : Number.POSITIVE_INFINITY
  const bProf =
    typeof b['Proficiency Level'] === 'number' ? b['Proficiency Level'] : Number.POSITIVE_INFINITY
  if (aProf !== bProf) return aProf - bProf
  return a['Display Name'].localeCompare(b['Display Name'])
}

/** @deprecated Use SkillMenuListItem */
export type SkillActionListItem = SkillMenuListItem
