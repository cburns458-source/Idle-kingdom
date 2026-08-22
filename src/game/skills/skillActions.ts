import type { ActionRow, GameDatabase, ItemRow, RequirementRow } from '../data/types'
import type { ProjectRow } from '../data/projectTypes'
import { requirementsForEntity } from '../activity/requirements'
import { COMBAT_SKILL_ID } from '../combat/stats'
import { ARTISANRY_SKILL_ID, ARCANA_SKILL_ID, SMITHING_SKILL_ID } from '../npcs/knowledge'
import { isCompleteRecipe } from '../production/recipes'
import {
  getEnchantment,
  isCompleteProject,
  isEnchantmentOutput,
  projectSkillRequirements,
} from '../projects/projects'

export const MINING_SKILL_ID = 'SKL-0002'
export const FISHING_SKILL_ID = 'SKL-0003'
export const HARVESTING_SKILL_ID = 'SKL-0004'
export const HUNTING_SKILL_ID = 'SKL-0005'
export const WOODCUTTING_SKILL_ID = 'SKL-0006'

const WOODEN_MINING_TOOLS = ['ITEM-0102']
const WOODEN_WOODCUTTING_TOOLS = ['ITEM-0100', 'ITEM-0101']
const WOODEN_FISHING_TOOLS = ['ITEM-0103']
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
  return db.Activities.filter((activity) => poolIds.has(activity['Pool ID']))
}

function isQuestOnlyRequirement(requirement: RequirementRow): boolean {
  const type = requirement['Requirement Type']
  return type === 'Quest Access' || type === 'Quest Flag' || type === 'Quest Active'
}

/** True when every activity that can roll this action is quest-gated. */
export function actionIsQuestOnly(db: GameDatabase, actionId: string): boolean {
  const activities = activitiesForAction(db, actionId)
  if (activities.length === 0) return false
  return activities.every((activity) =>
    requirementsForEntity(db, 'Activity', activity['Activity ID']).some(isQuestOnlyRequirement),
  )
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
  if (skillId === COMBAT_SKILL_ID) {
    return [
      listTab('enemies', 'Enemies', combatEnemyEntries(db)),
      listTab('gear', 'Weapons and equipment', combatGearEntries(db)),
    ]
  }
  if (
    skillId === MINING_SKILL_ID ||
    skillId === FISHING_SKILL_ID ||
    skillId === HARVESTING_SKILL_ID ||
    skillId === HUNTING_SKILL_ID ||
    skillId === WOODCUTTING_SKILL_ID
  ) {
    return [
      listTab('actions', 'Actions', actionsForSkill(db, skillId)),
      listTab('tools', 'Tools', gatheringToolEntries(db, skillId)),
    ]
  }
  if (skillId === SMITHING_SKILL_ID) return smithingTabs(db)
  if (skillId === ARTISANRY_SKILL_ID) return artisanryTabs(db)
  if (skillId === ARCANA_SKILL_ID) return arcanaTabs(db)
  return [listTab('actions', 'Actions', skillMenuEntries(db, skillId))]
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
  for (const project of projectsForSkill(db, ARTISANRY_SKILL_ID)) {
    const item = itemByName(db, project.displayName)
    if (isBowName(project.displayName)) bows.push(project)
    else if (isJewelryItem(item, project.displayName)) jewelry.push(project)
    else other.push(project)
  }
  return [
    listTab('bows', 'Bows', bows),
    listTab('jewelry', 'Jewelry', jewelry),
    listTab('other', 'Other', other),
  ]
}

function arcanaTabs(db: GameDatabase): SkillMenuTab[] {
  const spells: SkillMenuListItem[] = [...actionsForSkill(db, ARCANA_SKILL_ID)]
  const enchantments: SkillMenuListItem[] = []
  for (const project of projectsForSkill(db, ARCANA_SKILL_ID)) {
    const outputId = projectOutputId(db, project.id)
    if (isSpellName(project.displayName)) spells.push(project)
    else if (isEnchantmentName(project.displayName, outputId)) enchantments.push(project)
    else enchantments.push(project)
  }
  return [
    listTab('spells', 'Spells', dedupeByName(spells)),
    listTab('enchantments', 'Enchantments', dedupeByName(enchantments)),
  ]
}

function combatEnemyEntries(db: GameDatabase): SkillMenuListItem[] {
  const items: SkillMenuListItem[] = []
  const seen = new Set<string>()
  for (const action of db.Actions) {
    if (action['Relevant Skill ID'] !== COMBAT_SKILL_ID) continue
    if (action.Status === 'Needs Data') continue
    if (actionIsQuestOnly(db, action['Action ID'])) continue
    const enemy = enemyForCombatAction(db, action)
    if (!enemy) continue
    const name = enemy['Display Name'].trim()
    if (!name || seen.has(name)) continue
    seen.add(name)
    items.push({
      id: action['Action ID'],
      displayName: name,
      level: typeof enemy['Combat Level'] === 'number' ? enemy['Combat Level'] : null,
    })
  }
  return dedupeByName(items)
}

function combatGearEntries(db: GameDatabase): SkillMenuListItem[] {
  return dedupeByName([
    ...projectItemsWhere(db, (item) => isCombatGearItem(item), new Set([SMITHING_SKILL_ID, ARTISANRY_SKILL_ID])),
    ...woodenItems(db, WOODEN_COMBAT_GEAR),
  ])
}

function gatheringToolEntries(db: GameDatabase, skillId: string): SkillMenuListItem[] {
  const spec = gatheringToolSpec(skillId)
  if (!spec) return []
  return dedupeByName([
    ...projectItemsWhere(db, spec.match, null),
    ...woodenItems(db, spec.woodenIds),
  ])
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
      return { woodenIds: [], match: (_item, name) => isHuntingToolName(name) }
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
    items.push({ id: item['Item ID'], displayName: item['Display Name'], level: 1 })
  }
  return items
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

function compareMenuItems(a: SkillMenuListItem, b: SkillMenuListItem): number {
  const aLevel = a.level ?? Number.POSITIVE_INFINITY
  const bLevel = b.level ?? Number.POSITIVE_INFINITY
  if (aLevel !== bLevel) return aLevel - bLevel
  return a.displayName.localeCompare(b.displayName)
}

function smithingMaterial(name: string): string | null {
  const parts = name.trim().split(/\s+/)
  if (parts.length < 2) return null
  return parts[0] ?? null
}

function endsWithWord(name: string, word: string): boolean {
  return name === word || name.endsWith(` ${word}`)
}

function isWoodcuttingToolName(name: string): boolean {
  if (endsWithWord(name, 'Battleaxe')) return false
  return endsWithWord(name, 'Axe') || endsWithWord(name, 'Hatchet')
}

function isFishingToolName(name: string): boolean {
  return name.includes('Fishing Rod') || endsWithWord(name, 'Harpoon') || endsWithWord(name, 'Net')
}

function isHuntingToolName(name: string): boolean {
  return endsWithWord(name, 'Bow') || endsWithWord(name, 'Spear')
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

function isEnchantmentName(name: string, outputId: string): boolean {
  return outputId.startsWith('ENCH-') || name.includes('Enchantment') || name.includes('Enchanted')
}

function itemByName(db: GameDatabase, name: string): ItemRow | undefined {
  return db.Items.find((item) => item['Display Name'] === name)
}

function projectOutputId(db: GameDatabase, projectId: string): string {
  return db.Projects.find((row) => row['Project ID'] === projectId)?.['Output Item / Target ID'] ?? ''
}

function enemyForCombatAction(db: GameDatabase, action: ActionRow) {
  if (action.Category !== 'Combat') return undefined
  const targetId = action['Target ID']
  if (!targetId) return undefined
  return db.Enemies.find((row) => row['Enemy ID'] === targetId)
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
