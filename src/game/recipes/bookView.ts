import type { GameDatabase } from '../data/types'
import { getRecipe } from '../production/recipes'
import { getProject } from '../projects/projects'
import type { PlayerSave } from '../save/types'
import { skillMenuPlacementForOutput, skillMenuView } from '../skills/skillActions'
import { recipeBookForSkill, type RecipeBookEntry } from './knowledge'

export interface RecipeBookSection {
  title: string | null
  entries: RecipeBookEntry[]
}

export interface RecipeBookTab {
  id: string
  label: string
  sections: RecipeBookSection[]
}

export interface RecipeBookView {
  skillId: string
  tabs: RecipeBookTab[]
}

export function recipeBookSkillId(
  db: GameDatabase,
  entries: RecipeBookEntry[],
): string | null {
  const first = entries[0]
  if (!first) return null
  if (first.kind === 'recipe') {
    const skillId = getRecipe(db, first.id)?.['Skill ID']
    return typeof skillId === 'string' && skillId ? skillId : null
  }
  const skillId = getProject(db, first.id)?.['Skill ID']
  return typeof skillId === 'string' && skillId ? skillId : null
}

export function recipeBookView(
  save: PlayerSave,
  db: GameDatabase,
  skillId: string,
): RecipeBookView {
  return recipeBookViewForEntries(db, skillId, recipeBookForSkill(save, db, skillId))
}

export function recipeBookViewForEntries(
  db: GameDatabase,
  skillId: string,
  entries: RecipeBookEntry[],
): RecipeBookView {
  const buckets = new Map<
    string,
    { id: string; label: string; sections: Map<string, RecipeBookEntry[]>; order: string[] }
  >()
  const sectionKey = (title: string | null) => title ?? ''
  for (const entry of entries) {
    const outputId =
      entry.kind === 'project'
        ? (getProject(db, entry.id)?.['Output Item / Target ID'] ?? '')
        : (getRecipe(db, entry.id)?.['Output Item ID'] ?? '')
    const placement = skillMenuPlacementForOutput(db, skillId, entry.name, outputId)
    let bucket = buckets.get(placement.tabId)
    if (!bucket) {
      bucket = { id: placement.tabId, label: placement.tabLabel, sections: new Map(), order: [] }
      buckets.set(placement.tabId, bucket)
    }
    const key = sectionKey(placement.sectionTitle)
    if (!bucket.sections.has(key)) {
      bucket.order.push(key)
      bucket.sections.set(key, [])
    }
    bucket.sections.get(key)!.push(entry)
  }
  const tabOrder = skillMenuView(db, skillId).tabs.map((tab) => tab.id)
  const toTab = (bucket: {
    id: string
    label: string
    sections: Map<string, RecipeBookEntry[]>
    order: string[]
  }): RecipeBookTab => ({
    id: bucket.id,
    label: bucket.label,
    sections: bucket.order.map((key) => ({
      title: key.length === 0 ? null : key,
      entries: bucket.sections.get(key)!,
    })),
  })
  const tabs: RecipeBookTab[] = [
    ...tabOrder.flatMap((id) => {
      const bucket = buckets.get(id)
      return bucket ? [toTab(bucket)] : []
    }),
    ...[...buckets.values()].flatMap((bucket) =>
      tabOrder.includes(bucket.id) ? [] : [toTab(bucket)],
    ),
  ]
  if (tabs.length === 0) {
    return { skillId, tabs: [{ id: 'actions', label: 'Actions', sections: [] }] }
  }
  return { skillId, tabs }
}
