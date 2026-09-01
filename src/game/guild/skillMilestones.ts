/** Guild chat announcements when a member crosses skill thresholds. */

export interface GuildSkillMilestoneSettings {
  enabled: boolean
  /** First level that announces (default 50). */
  levelStart: number
  /** Level spacing (default 10). */
  levelStep: number
  /** First total-skill XP threshold in millions after level 100 (default 125). */
  xpStartMillion: number
  /** XP threshold spacing in millions (default 25). */
  xpStepMillion: number
}

export const DEFAULT_GUILD_SKILL_MILESTONE_SETTINGS: GuildSkillMilestoneSettings = {
  enabled: true,
  levelStart: 50,
  levelStep: 10,
  xpStartMillion: 125,
  xpStepMillion: 25,
}

const XP_MILLION = 1_000_000

export function normalizeGuildSkillMilestoneSettings(
  raw: Partial<GuildSkillMilestoneSettings> | null | undefined,
): GuildSkillMilestoneSettings {
  const base = DEFAULT_GUILD_SKILL_MILESTONE_SETTINGS
  if (!raw || typeof raw !== 'object') return { ...base }
  const levelStart = Math.max(1, Math.floor(Number(raw.levelStart) || base.levelStart))
  const levelStep = Math.max(1, Math.floor(Number(raw.levelStep) || base.levelStep))
  const xpStartMillion = Math.max(1, Math.floor(Number(raw.xpStartMillion) || base.xpStartMillion))
  const xpStepMillion = Math.max(1, Math.floor(Number(raw.xpStepMillion) || base.xpStepMillion))
  return {
    enabled: raw.enabled !== false,
    levelStart,
    levelStep,
    xpStartMillion,
    xpStepMillion,
  }
}

export type GuildSkillMilestone =
  | { kind: 'level'; skillId: string; skillName: string; level: number }
  | { kind: 'xp'; skillId: string; skillName: string; xpMillion: number }

export function formatGuildSkillMilestone(
  characterName: string,
  milestone: GuildSkillMilestone,
): string {
  const name = characterName.trim() || 'Adventurer'
  if (milestone.kind === 'level') {
    return `${name} reached ${milestone.skillName} ${milestone.level}`
  }
  return `${name} reached ${milestone.xpMillion}m ${milestone.skillName} XP`
}

/** True when [body] is a guild skill-milestone line, which already names the player. */
export function isGuildSkillMilestoneBody(body: string): boolean {
  const text = body.trim()
  return /^.+ reached .+ \d+$/.test(text) || /^.+ reached \d+m .+ XP$/.test(text)
}

/** Level thresholds at or below `level` starting from settings.levelStart. */
export function levelMilestonesAtOrBelow(
  level: number,
  settings: GuildSkillMilestoneSettings,
): number[] {
  if (level < settings.levelStart) return []
  const out: number[] = []
  for (let n = settings.levelStart; n <= level; n += settings.levelStep) {
    out.push(n)
  }
  return out
}

/** XP million thresholds at or below `xp` (only meaningful after level 100). */
export function xpMillionMilestonesAtOrBelow(
  xp: number,
  level: number,
  settings: GuildSkillMilestoneSettings,
): number[] {
  if (level < 100) return []
  const millions = Math.floor(xp / XP_MILLION)
  if (millions < settings.xpStartMillion) return []
  const out: number[] = []
  for (let n = settings.xpStartMillion; n <= millions; n += settings.xpStepMillion) {
    out.push(n)
  }
  return out
}

export function guildSkillMilestonesCrossed(args: {
  skillId: string
  skillName: string
  beforeLevel: number
  beforeXp: number
  afterLevel: number
  afterXp: number
  settings: GuildSkillMilestoneSettings
}): GuildSkillMilestone[] {
  const settings = normalizeGuildSkillMilestoneSettings(args.settings)
  if (!settings.enabled) return []
  if (args.afterLevel < args.beforeLevel && args.afterXp <= args.beforeXp) return []

  const beforeLevels = new Set(levelMilestonesAtOrBelow(args.beforeLevel, settings))
  const afterLevels = levelMilestonesAtOrBelow(args.afterLevel, settings)
  const out: GuildSkillMilestone[] = []
  for (const level of afterLevels) {
    if (!beforeLevels.has(level)) {
      out.push({
        kind: 'level',
        skillId: args.skillId,
        skillName: args.skillName,
        level,
      })
    }
  }

  const beforeXp = new Set(
    xpMillionMilestonesAtOrBelow(args.beforeXp, args.beforeLevel, settings),
  )
  const afterXp = xpMillionMilestonesAtOrBelow(args.afterXp, args.afterLevel, settings)
  for (const xpMillion of afterXp) {
    if (!beforeXp.has(xpMillion)) {
      out.push({
        kind: 'xp',
        skillId: args.skillId,
        skillName: args.skillName,
        xpMillion,
      })
    }
  }
  return out
}

export function guildSkillMilestonesBetweenSaves(args: {
  beforeSkills: Array<{ skillId: string; level: number; xp: number }>
  afterSkills: Array<{ skillId: string; level: number; xp: number }>
  skillName: (skillId: string) => string
  settings: GuildSkillMilestoneSettings
}): GuildSkillMilestone[] {
  const settings = normalizeGuildSkillMilestoneSettings(args.settings)
  if (!settings.enabled) return []
  const beforeById = new Map(args.beforeSkills.map((row) => [row.skillId, row]))
  const out: GuildSkillMilestone[] = []
  for (const after of args.afterSkills) {
    const before = beforeById.get(after.skillId)
    out.push(
      ...guildSkillMilestonesCrossed({
        skillId: after.skillId,
        skillName: args.skillName(after.skillId),
        beforeLevel: before?.level ?? 1,
        beforeXp: before?.xp ?? 0,
        afterLevel: after.level,
        afterXp: after.xp,
        settings,
      }),
    )
  }
  return out
}
