import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
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
  guildMemberSaveTotalLevel,
  normalizeGuildBanner,
  shouldCountRisingStrengthMembers,
  type GuildAchievementSnapshot,
} from './achievements'
import {
  GUILD_HALL_TIER_BANK,
  GUILD_HALL_TIER_BOXING,
  GUILD_HALL_TIER_BUILD,
  GUILD_HALL_TIER_GARDEN,
  guildHallMaterialsSpent,
  guildHallTierMaterialCount,
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

  it('counts a member with no save as total level 0 for Rising strength', () => {
    expect(guildMemberSaveTotalLevel(null)).toBe(0)
    expect(guildMemberSaveTotalLevel(undefined)).toBe(0)
    expect(
      evaluateGuildAchievements(snapshot({ membersAtLevel500: guildMemberSaveTotalLevel(null) }), NOW)
        .newlyUnlocked,
    ).not.toContain('gach_rising_strength')
  })

  it('skips the Rising strength member count once it is unlocked', () => {
    expect(shouldCountRisingStrengthMembers(undefined)).toBe(true)
    expect(shouldCountRisingStrengthMembers({})).toBe(true)
    const reached = evaluateGuildAchievements(snapshot({ membersAtLevel500: 25 }), NOW)
    expect(shouldCountRisingStrengthMembers(reached.unlocked)).toBe(false)
    const skipped = evaluateGuildAchievements(
      snapshot({ membersAtLevel500: 0, unlocked: reached.unlocked }),
      '2026-10-16T13:00:00.000Z',
    )
    expect(skipped.newlyUnlocked).toEqual([])
    expect(skipped.unlocked.gach_rising_strength).toBe(NOW)
    const qaSql = readFileSync(
      resolve(process.cwd(), 'supabase/migrations/20261016190000_guild_achievements_skip_rising_count.sql'),
      'utf8',
    )
    const skipAt = qaSql.indexOf("a.achievement_id = 'gach_rising_strength'")
    const countAt = qaSql.indexOf('bazaar_user_total_level')
    expect(skipAt).toBeGreaterThan(0)
    expect(countAt).toBeGreaterThan(skipAt)
    expect(qaSql).toContain('v_new_level < 500 or v_old_level >= 500')
  })

  it('keeps rising strength unlocked after a member leaves', () => {
    // Vari: Rising strength stays unlocked after members leave.
    const reached = evaluateGuildAchievements(snapshot({ membersAtLevel500: 25 }), NOW)
    expect(reached.newlyUnlocked).toEqual(['gach_rising_strength'])
    const afterLeave = evaluateGuildAchievements(
      snapshot({ membersAtLevel500: 24, unlocked: reached.unlocked }),
      '2026-10-16T13:00:00.000Z',
    )
    expect(afterLeave.newlyUnlocked).toEqual([])
    expect(afterLeave.unlocked.gach_rising_strength).toBe(NOW)
    expect(afterLeave.progress.find((row) => row.id === 'gach_rising_strength')?.unlocked).toBe(true)
  })

  it('SQL hall tier material costs match guildHallTierMaterialCount (202700 all six)', () => {
    const sql = readFileSync(
      resolve(process.cwd(), 'supabase/migrations/20261016170000_guild_achievements_and_banner.sql'),
      'utf8',
    )
    const costs = new Map<string, number>()
    for (const match of sql.matchAll(/when '([^']+)' then (\d+)/g)) {
      costs.set(match[1], Number(match[2]))
    }
    let sqlTotal = 0
    let tsTotal = 0
    for (const tier of GUILD_HALL_TIERS) {
      expect(costs.get(tier.id), tier.id).toBe(guildHallTierMaterialCount(tier))
      sqlTotal += costs.get(tier.id) ?? 0
      tsTotal += guildHallTierMaterialCount(tier)
    }
    expect(tsTotal).toBe(202_700)
    expect(sqlTotal).toBe(202_700)
    expect(guildHallMaterialsSpent(GUILD_HALL_TIERS.map((tier) => tier.id))).toBe(202_700)
  })

  it('hosted game function counts rising strength from saves, not roster total_level', () => {
    const gameSource = readFileSync(resolve(process.cwd(), 'supabase/functions/game/index.ts'), 'utf8')
    expect(gameSource).toContain('countMembersAtSaveLevel500')
    expect(gameSource).toContain('hostedTotalLevel')
    expect(gameSource).toContain('unlockedAchievements.gach_rising_strength')
    expect(gameSource).not.toMatch(/\.gte\('total_level',\s*500\)/)
    const qaSql = readFileSync(
      resolve(process.cwd(), 'supabase/migrations/20261016180000_guild_achievements_qa.sql'),
      'utf8',
    )
    expect(qaSql).toContain('bazaar_user_total_level')
    expect(qaSql).toMatch(/when sqlstate 'P0001'/)
    expect(qaSql).not.toMatch(/when others then/)
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
