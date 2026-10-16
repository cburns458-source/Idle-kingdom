import { describe, expect, it } from 'vitest'
import {
  DEFAULT_GUILD_BANNER,
  evaluateGuildAchievements,
  GUILD_ACHIEVEMENT_GOLD_100K,
  GUILD_ACHIEVEMENT_MATERIALS,
  GUILD_ACHIEVEMENTS,
  GUILD_BANNER_BORDER_REFUSAL,
  GUILD_BANNER_COLOUR_REFUSAL,
  GUILD_BANNER_EMBLEM_REFUSAL,
  GUILD_BANNER_PALETTE,
  guildAchievementCurrent,
  guildDonorIds,
  guildMaySetBanner,
  normalizeGuildBanner,
  type GuildAchievementSnapshot,
} from './achievements'
import {
  GUILD_HALL_TIER_BANK,
  GUILD_HALL_TIER_BOXING,
  GUILD_HALL_TIER_BUILD,
  GUILD_HALL_TIER_GARDEN,
  guildHallMaterialsSpent,
  GUILD_HALL_TIERS,
} from './hall'

const NOW = '2026-10-16T12:00:00.000Z'

function snapshot(partial: Partial<GuildAchievementSnapshot> = {}): GuildAchievementSnapshot {
  return {
    completedTiers: [],
    goldContributed: 0,
    goldContributedBy: {},
    membersAtLevel500: 0,
    ...partial,
  }
}

describe('guild achievements and banner', () => {
  it('keeps placeholder names in one catalog Quest can edit', () => {
    expect(GUILD_ACHIEVEMENTS.map((row) => row.id)).toEqual([
      'gach_foundations',
      'gach_hall_2',
      'gach_hall_3',
      'gach_hall_4',
      'gach_hall_arcana',
      'gach_hall_5',
      'gach_gold_100k',
      'gach_gold_500k',
      'gach_materials',
      'gach_donors_10',
      'gach_donors_25',
      'gach_rising_strength',
    ])
    expect(GUILD_ACHIEVEMENTS.map((row) => row.name)).toEqual([
      'Foundations laid',
      'Raised walls',
      'Under one roof',
      'Banners high',
      'Arcane corner',
      'A hall fit for kings',
      'Deep pockets',
      'Deeper pockets',
      'Stocked vault',
      'Many hands',
      'More hands',
      'Rising strength',
    ])
    expect(GUILD_ACHIEVEMENTS.some((row) => /coffer/i.test(`${row.name} ${row.description}`))).toBe(
      false,
    )
  })

  it('unlocks each hall step once, including arcana and the 1M cage', () => {
    const first = evaluateGuildAchievements(snapshot({ completedTiers: [GUILD_HALL_TIER_BUILD] }), NOW)
    expect(first.newlyUnlocked).toEqual(['gach_foundations'])
    const again = evaluateGuildAchievements(
      snapshot({
        completedTiers: [GUILD_HALL_TIER_BUILD],
        unlocked: first.unlocked,
      }),
      '2026-10-16T13:00:00.000Z',
    )
    expect(again.newlyUnlocked).toEqual([])
    expect(again.unlocked.gach_foundations).toBe(NOW)

    const allTiers = GUILD_HALL_TIERS.map((tier) => tier.id)
    const done = evaluateGuildAchievements(snapshot({ completedTiers: allTiers, goldContributed: 1_000_000 }), NOW)
    expect(done.newlyUnlocked).toEqual(
      expect.arrayContaining([
        'gach_foundations',
        'gach_hall_2',
        'gach_hall_3',
        'gach_hall_4',
        'gach_hall_arcana',
        'gach_hall_5',
        'gach_gold_100k',
        'gach_gold_500k',
      ]),
    )
    expect(done.progress.find((row) => row.id === 'gach_hall_5')?.unlocked).toBe(true)
  })

  it('counts gold, hall-build materials, and distinct donors; bank deposits do not count', () => {
    expect(guildAchievementCurrent(GUILD_ACHIEVEMENTS.find((row) => row.id === 'gach_gold_100k')!, snapshot({ goldContributed: 99_999 }))).toBe(
      99_999,
    )
    const gold = evaluateGuildAchievements(snapshot({ goldContributed: GUILD_ACHIEVEMENT_GOLD_100K }), NOW)
    expect(gold.newlyUnlocked).toContain('gach_gold_100k')
    expect(gold.newlyUnlocked).not.toContain('gach_gold_500k')

    const afterGarden = [
      GUILD_HALL_TIER_BUILD,
      GUILD_HALL_TIER_BANK,
      GUILD_HALL_TIER_BOXING,
      GUILD_HALL_TIER_GARDEN,
    ]
    expect(guildHallMaterialsSpent(afterGarden)).toBeGreaterThanOrEqual(GUILD_ACHIEVEMENT_MATERIALS)
    const vault = evaluateGuildAchievements(snapshot({ completedTiers: afterGarden }), NOW)
    expect(vault.newlyUnlocked).toContain('gach_materials')
    expect(guildHallMaterialsSpent([GUILD_HALL_TIER_BUILD])).toBe(1100)

    const donors = Object.fromEntries(Array.from({ length: 10 }, (_, i) => [`u${i}`, 1]))
    const many = evaluateGuildAchievements(snapshot({ goldContributedBy: donors }), NOW)
    expect(many.newlyUnlocked).toContain('gach_donors_10')
    expect(many.newlyUnlocked).not.toContain('gach_donors_25')

    const materialsOnly = evaluateGuildAchievements(
      snapshot({ donatedBy: { a: true, b: true } }),
      NOW,
    )
    expect(guildDonorIds({ donatedBy: { a: true, b: true }, goldContributedBy: { a: 5 } })).toHaveLength(2)
    expect(materialsOnly.progress.find((row) => row.id === 'gach_donors_10')?.current).toBe(2)
  })

  it('unlocks rising strength at 25 members of total level 500', () => {
    const short = evaluateGuildAchievements(snapshot({ membersAtLevel500: 24 }), NOW)
    expect(short.newlyUnlocked).not.toContain('gach_rising_strength')
    const reached = evaluateGuildAchievements(snapshot({ membersAtLevel500: 25 }), NOW)
    expect(reached.newlyUnlocked).toEqual(['gach_rising_strength'])
    expect(reached.progress.find((row) => row.id === 'gach_rising_strength')).toMatchObject({
      current: 25,
      target: 25,
      unlocked: true,
    })
  })

  it('exposes current/target progress for every achievement', () => {
    const progress = evaluateGuildAchievements(
      snapshot({ goldContributed: 40_000, membersAtLevel500: 3 }),
      NOW,
    ).progress
    expect(progress).toHaveLength(GUILD_ACHIEVEMENTS.length)
    const pockets = progress.find((row) => row.id === 'gach_gold_100k')
    expect(pockets).toMatchObject({ current: 40_000, target: 100_000, unlocked: false, unlockedAt: null })
  })

  it('validates banner colours and requires unlocked emblem and border', () => {
    expect(GUILD_BANNER_PALETTE).not.toContain('green')
    expect(GUILD_BANNER_PALETTE).not.toContain('gold')
    expect(guildMaySetBanner('leader')).toBe(true)
    expect(guildMaySetBanner('officer')).toBe(true)
    expect(guildMaySetBanner('veteran')).toBe(false)
    expect(normalizeGuildBanner(null).ok).toBe(true)
    expect(normalizeGuildBanner({ background: 'moss', accent: 'ivory' })).toEqual({
      ok: false,
      reason: GUILD_BANNER_COLOUR_REFUSAL,
    })
    expect(
      normalizeGuildBanner({
        background: 'slate',
        accent: 'ivory',
        emblem: 'emblem_foundations',
      }),
    ).toEqual({ ok: false, reason: GUILD_BANNER_EMBLEM_REFUSAL })
    const unlocked = normalizeGuildBanner(
      { background: 'wine', accent: 'ivory', emblem: 'emblem_foundations', border: 'border_vault' },
      ['gach_foundations', 'gach_materials'],
    )
    expect(unlocked).toEqual({
      ok: true,
      banner: {
        background: 'wine',
        accent: 'ivory',
        emblem: 'emblem_foundations',
        border: 'border_vault',
      },
    })
    expect(
      normalizeGuildBanner(
        { ...DEFAULT_GUILD_BANNER, border: 'border_vault' },
        ['gach_foundations'],
      ),
    ).toEqual({ ok: false, reason: GUILD_BANNER_BORDER_REFUSAL })
  })
})
