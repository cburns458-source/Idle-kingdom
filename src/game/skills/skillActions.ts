import type { ActionRow, GameDatabase } from '../data/types'

export interface SkillActionListItem {
  actionId: string
  displayName: string
  proficiencyLevel: number | null
}

/** Actions for a skill menu: display names only, unique by name, proficiency when set. */
export function actionsForSkill(db: GameDatabase, skillId: string): SkillActionListItem[] {
  const rows = db.Actions.filter(
    (action) =>
      action['Relevant Skill ID'] === skillId &&
      action.Status !== 'Needs Data' &&
      Boolean(action['Display Name']?.trim()),
  )

  rows.sort(compareSkillActions)

  const seen = new Set<string>()
  const items: SkillActionListItem[] = []
  for (const action of rows) {
    const displayName = action['Display Name']!.trim()
    if (seen.has(displayName)) continue
    seen.add(displayName)
    const proficiency = action['Proficiency Level']
    items.push({
      actionId: action['Action ID'],
      displayName,
      proficiencyLevel: typeof proficiency === 'number' ? proficiency : null,
    })
  }
  return items
}

function compareSkillActions(a: ActionRow, b: ActionRow): number {
  const aProf = typeof a['Proficiency Level'] === 'number' ? a['Proficiency Level'] : Number.POSITIVE_INFINITY
  const bProf = typeof b['Proficiency Level'] === 'number' ? b['Proficiency Level'] : Number.POSITIVE_INFINITY
  if (aProf !== bProf) return aProf - bProf
  return a['Display Name'].localeCompare(b['Display Name'])
}
