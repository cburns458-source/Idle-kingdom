import type { RecipeRow } from '../data/recipeTypes'
import type { GameDatabase } from '../data/types'
import { getSkillProgress } from '../activity/xp'
import { hasProjectKnowledge } from '../npcs/knowledge'
import {
  facilityIdForActivity,
  getRecipe,
  isCompleteRecipe,
  recipeMatchesFacility,
} from '../production/recipes'
import { getProject, isCompleteProject } from '../projects/projects'
import type { PlayerSave } from '../save/types'

function knowledgeSourceOf(recipe: RecipeRow): string {
  return String(recipe['Knowledge Source'] ?? '').trim()
}

/**
 * Level-unlock recipes (empty / "automatic" / "level unlock") appear as soon as
 * the player reaches the proficiency. Any other Knowledge Source is a taught
 * recipe: it stays locked until `unlockedRecipeIds` includes it.
 *
 * Smithing is skill-taught via a mentor (`knowsProject` / `hasProjectKnowledge`),
 * so individual smithing rows are not separately locked. Cooking and crafting
 * currently have no teacher — they stay automatic. Later taught recipes just
 * need a non-automatic Knowledge Source; this gate already handles them.
 */
export function isAutomaticLevelUnlock(recipe: RecipeRow): boolean {
  const source = knowledgeSourceOf(recipe).toLowerCase()
  return !source || source.includes('automatic') || source.includes('level unlock')
}

/** Whether the player knows a production recipe (can craft if otherwise eligible). */
export function knowsRecipe(save: PlayerSave, db: GameDatabase, recipeId: string): boolean {
  if ((save.unlockedRecipeIds ?? []).includes(recipeId)) return true
  const recipe = getRecipe(db, recipeId)
  if (!recipe || !isCompleteRecipe(recipe)) return false
  if (!isAutomaticLevelUnlock(recipe)) return false
  const level = getSkillProgress(save, recipe['Skill ID']).level
  return level >= recipe['Proficiency Level']
}

/** Hard proficiency + knowledge-source gate used by production lists. */
export function canKnowRecipe(save: PlayerSave, db: GameDatabase, recipe: RecipeRow): boolean {
  return knowsRecipe(save, db, recipe['Recipe ID'])
}

export function unlockRecipeId(save: PlayerSave, recipeId: string): PlayerSave {
  const id = recipeId.trim()
  if (!id) return save
  const known = save.unlockedRecipeIds ?? []
  if (known.includes(id)) return save
  return { ...save, unlockedRecipeIds: [...known, id] }
}

export function knowsProject(save: PlayerSave, db: GameDatabase, projectId: string): boolean {
  const project = getProject(db, projectId)
  if (!project || !isCompleteProject(project)) return false
  return hasProjectKnowledge(db, save, project['Skill ID']).ok
}

export type RecipeBookEntry =
  | {
      kind: 'recipe'
      id: string
      known: boolean
      name: string
      skill: string
      proficiency: number
      station: string
      location: string
      output: string
      materials: string
      knowledgeSource: string
      hintUnknown: boolean
    }
  | {
      kind: 'project'
      id: string
      known: boolean
      name: string
      skill: string
      proficiency: number
      station: string
      location: string
      output: string
      materials: string
      knowledgeSource: string
      hintUnknown: boolean
    }

function itemName(db: GameDatabase, itemId: string | null | undefined): string {
  if (!itemId) return '—'
  return db.Items.find((item) => item['Item ID'] === itemId)?.['Display Name'] ?? itemId
}

function facilityLabel(db: GameDatabase, facilityId: string | null | undefined): {
  station: string
  location: string
} {
  if (!facilityId) return { station: '—', location: '—' }
  const facility = db.Facilities.find((row) => row['Facility ID'] === facilityId)
  if (!facility) return { station: facilityId, location: '—' }
  const location =
    db.Locations.find((row) => row['Location ID'] === facility['Location ID'])?.[
      'Display Name'
    ] ?? '—'
  return { station: facility['Display Name'] ?? facilityId, location }
}

export function listRecipeBookEntries(save: PlayerSave, db: GameDatabase): RecipeBookEntry[] {
  const recipes: RecipeBookEntry[] = db.Recipes.filter(isCompleteRecipe).map((recipe) => {
    const known = knowsRecipe(save, db, recipe['Recipe ID'])
    const skill =
      db.Skills.find((row) => row['Skill ID'] === recipe['Skill ID'])?.['Display Name'] ??
      recipe['Skill ID']
    const place = facilityLabel(db, recipe['Facility ID'])
    const ingredients = [
      recipe['Ingredient 1 Item ID']
        ? `${itemName(db, recipe['Ingredient 1 Item ID'])} ×${recipe['Ingredient 1 Quantity'] ?? 1}`
        : null,
      recipe['Ingredient 2 Item ID']
        ? `${itemName(db, recipe['Ingredient 2 Item ID'])} ×${recipe['Ingredient 2 Quantity'] ?? 1}`
        : null,
      recipe['Ingredient 3 Item ID']
        ? `${itemName(db, recipe['Ingredient 3 Item ID'])} ×${recipe['Ingredient 3 Quantity'] ?? 1}`
        : null,
      recipe['Ingredient 4 Item ID']
        ? `${itemName(db, recipe['Ingredient 4 Item ID'])} ×${recipe['Ingredient 4 Quantity'] ?? 1}`
        : null,
    ]
      .filter(Boolean)
      .join(', ')
    const source = knowledgeSourceOf(recipe) || 'Automatic level unlock'
    return {
      kind: 'recipe',
      id: recipe['Recipe ID'],
      known,
      name: recipe['Display Name'],
      skill,
      proficiency: recipe['Proficiency Level'],
      station: place.station,
      location: place.location,
      output: `${itemName(db, recipe['Output Item ID'])} ×${recipe['Output Quantity']}`,
      materials: ingredients || '—',
      knowledgeSource: source,
      hintUnknown: !known && !isAutomaticLevelUnlock(recipe),
    }
  })

  const projects: RecipeBookEntry[] = db.Projects.filter(isCompleteProject).map((project) => {
    const known = knowsProject(save, db, project['Project ID'])
    const skill =
      db.Skills.find((row) => row['Skill ID'] === project['Skill ID'])?.['Display Name'] ??
      project['Skill ID']
    const place = facilityLabel(db, project['Facility ID'])
    const materials = [
      project['Input 1 Item ID']
        ? `${itemName(db, project['Input 1 Item ID'])} ×${project['Input 1 Quantity'] ?? 1}`
        : null,
      project['Input 2 Item ID']
        ? `${itemName(db, project['Input 2 Item ID'])} ×${project['Input 2 Quantity'] ?? 1}`
        : null,
      project['Input 3 Item ID']
        ? `${itemName(db, project['Input 3 Item ID'])} ×${project['Input 3 Quantity'] ?? 1}`
        : null,
      project['Input 4 Item ID']
        ? `${itemName(db, project['Input 4 Item ID'])} ×${project['Input 4 Quantity'] ?? 1}`
        : null,
    ]
      .filter(Boolean)
      .join(', ')
    const knowledge = hasProjectKnowledge(db, save, project['Skill ID'])
    const source = !knowledge.ok
      ? `Mentor: ${knowledge.npcName}`
      : 'Mentor unlock'
    return {
      kind: 'project',
      id: project['Project ID'],
      known,
      name: project['Display Name'],
      skill,
      proficiency: projectSkillFloor(project),
      station: place.station,
      location: place.location,
      output: isEnchantOutput(project['Output Item / Target ID'])
        ? project['Display Name']
        : `${itemName(db, project['Output Item / Target ID'])} ×${project['Output Quantity']}`,
      materials: materials || (project['Gold Cost'] > 0 ? `${project['Gold Cost']} gold` : '—'),
      knowledgeSource: source,
      hintUnknown: !known,
    }
  })

  return [...recipes, ...projects].sort((a, b) => {
    if (a.proficiency !== b.proficiency) return a.proficiency - b.proficiency
    return a.name.localeCompare(b.name)
  })
}

/** Recipes and mentor projects for one skill, including locked rows. */
export function recipeBookForSkill(
  save: PlayerSave,
  db: GameDatabase,
  skillId: string,
): RecipeBookEntry[] {
  return listRecipeBookEntries(save, db).filter((entry) => {
    if (entry.kind === 'recipe') {
      return getRecipe(db, entry.id)?.['Skill ID'] === skillId
    }
    return getProject(db, entry.id)?.['Skill ID'] === skillId
  })
}

/** Every recipe at this station, including locked and unknown ones. */
export function recipeBookForActivity(
  save: PlayerSave,
  db: GameDatabase,
  activityId: string,
): RecipeBookEntry[] {
  const facilityId = facilityIdForActivity(db, activityId)
  if (!facilityId) return []
  return listRecipeBookEntries(save, db).filter((entry) => {
    if (entry.kind !== 'recipe') return false
    const recipe = getRecipe(db, entry.id)
    return recipe != null && recipeMatchesFacility(recipe['Facility ID'], facilityId)
  })
}

function projectSkillFloor(project: {
  'Required Skill 1 Level': number | null
}): number {
  return typeof project['Required Skill 1 Level'] === 'number'
    ? project['Required Skill 1 Level']
    : 1
}

function isEnchantOutput(outputId: string): boolean {
  return outputId.startsWith('ENCH-')
}
