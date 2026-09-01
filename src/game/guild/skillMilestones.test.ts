import { describe, expect, it } from 'vitest'
import {
  DEFAULT_GUILD_SKILL_MILESTONE_SETTINGS,
  formatGuildSkillMilestone,
  guildSkillMilestonesCrossed,
  isGuildSkillMilestoneBody,
} from './skillMilestones'

describe('guild skill milestones', () => {
  const settings = DEFAULT_GUILD_SKILL_MILESTONE_SETTINGS

  it('emits every missed level threshold in a jump', () => {
    const crossed = guildSkillMilestonesCrossed({
      skillId: 'SKL-0002',
      skillName: 'Mining',
      beforeLevel: 49,
      beforeXp: 0,
      afterLevel: 72,
      afterXp: 1,
      settings,
    })
    expect(crossed.map((row) => (row.kind === 'level' ? row.level : null))).toEqual([
      50, 60, 70,
    ])
  })

  it('emits XP million thresholds only after level 100', () => {
    const early = guildSkillMilestonesCrossed({
      skillId: 'SKL-0002',
      skillName: 'Mining',
      beforeLevel: 90,
      beforeXp: 120_000_000,
      afterLevel: 95,
      afterXp: 160_000_000,
      settings,
    })
    expect(early).toEqual([])

    const late = guildSkillMilestonesCrossed({
      skillId: 'SKL-0002',
      skillName: 'Mining',
      beforeLevel: 100,
      beforeXp: 124_000_000,
      afterLevel: 100,
      afterXp: 151_000_000,
      settings,
    })
    expect(late.map((row) => (row.kind === 'xp' ? row.xpMillion : null))).toEqual([125, 150])
  })

  it('formats chat lines', () => {
    expect(
      formatGuildSkillMilestone('Vari', {
        kind: 'level',
        skillId: 'SKL-0002',
        skillName: 'Mining',
        level: 60,
      }),
    ).toBe('Vari reached Mining 60')
    expect(
      formatGuildSkillMilestone('Vari', {
        kind: 'xp',
        skillId: 'SKL-0002',
        skillName: 'Mining',
        xpMillion: 125,
      }),
    ).toBe('Vari reached 125m Mining XP')
  })

  it('recognizes milestone bodies so chat can drop the username prefix', () => {
    expect(isGuildSkillMilestoneBody('Vari reached Mining 60')).toBe(true)
    expect(isGuildSkillMilestoneBody('Vari reached 125m Mining XP')).toBe(true)
    expect(isGuildSkillMilestoneBody('Hello guild')).toBe(false)
  })
})
