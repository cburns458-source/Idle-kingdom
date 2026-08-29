import { activityVisibleForSave, requirementsForEntity } from '../activity/requirements'
import type { ActionRow, ActivityRow, GameDatabase } from '../data/types'
import { isCompleteRecipe } from '../production/recipes'
import { isCompleteProject, meetsProjectKnowledge, meetsProjectSkills, projectSkillRequirements } from '../projects/projects'
import { knowsRecipe } from '../recipes/knowledge'
import type { PlayerSave } from '../save/types'

export interface SkillUnlockSummary {
  unlockedActivities: string[]
  proficientActivities: string[]
  recipes: string[]
  projects: string[]
}

export interface SkillLevelUpNotice {
  skillId: string
  skillName: string
  level: number
  unlocks: SkillUnlockSummary
}

function inLevelRange(value: number, fromLevel: number, toLevel: number): boolean {
  return value > fromLevel && value <= toLevel
}

function skillName(db: GameDatabase, skillId: string): string {
  const name = db.Skills.find((skill) => skill['Skill ID'] === skillId)?.['Display Name']
  return name ? name : skillId
}

function activityName(activity: ActivityRow): string {
  const contextual = typeof activity['Contextual Name'] === 'string' ? activity['Contextual Name'].trim() : ''
  return contextual || activity['Activity ID']
}

function actionsForActivity(db: GameDatabase, activity: ActivityRow): ActionRow[] {
  const poolId = activity['Pool ID']
  if (!poolId) return []
  const actionIds = new Set(
    db.PoolEntries.filter((entry) => entry['Pool ID'] === poolId).map((entry) => entry['Action ID']),
  )
  if (actionIds.size === 0) return []
  return db.Actions.filter((action) => actionIds.has(action['Action ID']))
}

function uniqueSorted(names: Iterable<string>): string[] {
  const out = [...new Set([...names].filter((name) => name.trim().length > 0))]
  out.sort((a, b) => a.localeCompare(b))
  return out
}

/** Names unlocked between `fromLevel` (exclusive) and `toLevel` (inclusive). */
export function skillUnlocksBetween(
  db: GameDatabase,
  saveAfter: PlayerSave,
  skillId: string,
  fromLevel: number,
  toLevel: number,
): SkillUnlockSummary {
  if (toLevel <= fromLevel) {
    return { unlockedActivities: [], proficientActivities: [], recipes: [], projects: [] }
  }

  const unlocked: string[] = []
  const proficient: string[] = []

  for (const activity of db.Activities) {
    if (activity.Status === 'Needs Data') continue
    if (!activityVisibleForSave(db, saveAfter, activity['Activity ID'])) continue
    const name = activityName(activity)

    for (const requirement of requirementsForEntity(db, 'Activity', activity['Activity ID'])) {
      if (requirement['Requirement Type'] !== 'Skill Level') continue
      if (String(requirement.Operator ?? '').toLowerCase() === 'proficiency') continue
      if (String(requirement['Reference ID / Value'] ?? '') !== skillId) continue
      const required = requirement['Required Value']
      if (typeof required === 'number' && inLevelRange(required, fromLevel, toLevel)) {
        unlocked.push(name)
      }
    }

    for (const action of actionsForActivity(db, activity)) {
      if (action.Status === 'Needs Data') continue
      if (action['Relevant Skill ID'] !== skillId) continue
      const proficiency = action['Proficiency Level']
      if (typeof proficiency === 'number' && inLevelRange(proficiency, fromLevel, toLevel)) {
        proficient.push(name)
      }
    }
  }

  const recipes: string[] = []
  for (const recipe of db.Recipes.filter(isCompleteRecipe)) {
    if (recipe['Skill ID'] !== skillId) continue
    if (!knowsRecipe(saveAfter, db, recipe['Recipe ID'])) continue
    const proficiency = recipe['Proficiency Level']
    if (typeof proficiency === 'number' && inLevelRange(proficiency, fromLevel, toLevel)) {
      recipes.push(recipe['Display Name'])
    }
  }

  const projects: string[] = []
  for (const project of db.Projects.filter(isCompleteProject)) {
    if (!meetsProjectKnowledge(db, saveAfter, project)) continue
    if (!meetsProjectSkills(saveAfter, project)) continue
    const hit = projectSkillRequirements(project).some(
      (requirement) =>
        requirement.skillId === skillId && inLevelRange(requirement.level, fromLevel, toLevel),
    )
    if (hit) projects.push(project['Display Name'])
  }

  const unlockedActivities = uniqueSorted(unlocked)
  const unlockedSet = new Set(unlockedActivities)
  return {
    unlockedActivities,
    proficientActivities: uniqueSorted(proficient.filter((name) => !unlockedSet.has(name))),
    recipes: uniqueSorted(recipes),
    projects: uniqueSorted(projects),
  }
}

/** Skills that rose from `before` to `after`, each with the unlocks in that jump. */
export function skillLevelUpsBetween(
  db: GameDatabase,
  before: PlayerSave,
  after: PlayerSave,
): SkillLevelUpNotice[] {
  const fromLevels = new Map(before.skills.map((skill) => [skill.skillId, skill.level] as const))
  const notices: SkillLevelUpNotice[] = []
  const seen = new Set<string>()
  for (const skill of after.skills) {
    if (seen.has(skill.skillId)) continue
    seen.add(skill.skillId)
    const from = fromLevels.get(skill.skillId) ?? 1
    if (skill.level <= from) continue
    notices.push({
      skillId: skill.skillId,
      skillName: skillName(db, skill.skillId),
      level: skill.level,
      unlocks: skillUnlocksBetween(db, after, skill.skillId, from, skill.level),
    })
  }
  notices.sort((a, b) => a.skillName.localeCompare(b.skillName))
  return notices
}
