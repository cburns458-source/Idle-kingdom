import type { PlayerSave } from '../save/types'
import { totalLevel } from '../skills/totals'
import {
  GUILD_HALL_TIER_ARCANA,
  GUILD_HALL_TIER_BANK,
  GUILD_HALL_TIER_BOXING,
  GUILD_HALL_TIER_BUILD,
  GUILD_HALL_TIER_CAGE,
  GUILD_HALL_TIER_GARDEN,
  guildHallMaterialsSpent,
} from './hall'

/** Palette ids for banner fill and accent. Hex values are a UI choice. */
export const GUILD_BANNER_PALETTE = [
  'slate',
  'midnight',
  'wine',
  'rust',
  'ivory',
  'ash',
  'indigo',
  'ocean',
  'ember',
  'plum',
] as const

export type GuildBannerPaletteId = (typeof GUILD_BANNER_PALETTE)[number]

export const GUILD_BANNER_DEFAULT_BACKGROUND: GuildBannerPaletteId = 'slate'
export const GUILD_BANNER_DEFAULT_ACCENT: GuildBannerPaletteId = 'ivory'

export type GuildBannerRewardKind = 'emblem' | 'border'

export type GuildBanner = {
  background: GuildBannerPaletteId
  accent: GuildBannerPaletteId
  emblem: string | null
  border: string | null
}

export const DEFAULT_GUILD_BANNER: GuildBanner = {
  background: GUILD_BANNER_DEFAULT_BACKGROUND,
  accent: GUILD_BANNER_DEFAULT_ACCENT,
  emblem: null,
  border: null,
}

export const GUILD_ACHIEVEMENT_GOLD_100K = 100_000
export const GUILD_ACHIEVEMENT_GOLD_500K = 500_000
export const GUILD_ACHIEVEMENT_MATERIALS = 100_000
export const GUILD_ACHIEVEMENT_DONORS_10 = 10
export const GUILD_ACHIEVEMENT_DONORS_25 = 25
/** Hosted-save totalLevel gate. Count via totalLevel(parseSave(...)), never guild_members.total_level. */
export const GUILD_ACHIEVEMENT_MEMBER_LEVEL = 500
export const GUILD_ACHIEVEMENT_MEMBERS_AT_LEVEL = 25

/**
 * Rising strength reads the hosted save, same as SQL bazaar_user_total_level.
 * A member with no save counts as 0. Do not use guild_members.total_level.
 */
export function guildMemberSaveTotalLevel(save: Pick<PlayerSave, 'skills'> | null | undefined): number {
  return save == null ? 0 : totalLevel(save)
}

/** False once Rising strength is unlocked; skip the hosted-save member scan. */
export function shouldCountRisingStrengthMembers(unlocked: Record<string, string> | undefined): boolean {
  return unlocked?.gach_rising_strength == null
}

export type GuildAchievementKind = 'hall_tier' | 'gold' | 'materials' | 'donors' | 'members_level'

export type GuildAchievementDef = {
  id: string
  name: string
  description: string
  rewardKind: GuildBannerRewardKind
  rewardId: string
  kind: GuildAchievementKind
  target: number
  /** Hall-tier achievements unlock when this completed_tiers id is present. */
  tierId?: string
}

/**
 * Guild-wide cosmetics. Quest owns the names and descriptions; keep them in
 * this list so they can edit one place.
 */
export const GUILD_ACHIEVEMENTS: readonly GuildAchievementDef[] = [
  {
    id: 'gach_foundations',
    name: 'Foundations laid',
    description: 'Build the first tier of the guild hall.',
    rewardKind: 'emblem',
    rewardId: 'emblem_foundations',
    kind: 'hall_tier',
    target: 1,
    tierId: GUILD_HALL_TIER_BUILD,
  },
  {
    id: 'gach_hall_2',
    name: 'Raised walls',
    description: 'Build tier 2 of the guild hall.',
    rewardKind: 'emblem',
    rewardId: 'emblem_counting',
    kind: 'hall_tier',
    target: 1,
    tierId: GUILD_HALL_TIER_BANK,
  },
  {
    id: 'gach_hall_3',
    name: 'Under one roof',
    description: 'Build tier 3 of the guild hall.',
    rewardKind: 'emblem',
    rewardId: 'emblem_boxing',
    kind: 'hall_tier',
    target: 1,
    tierId: GUILD_HALL_TIER_BOXING,
  },
  {
    id: 'gach_hall_4',
    name: 'Banners high',
    description: 'Build tier 4 of the guild hall.',
    rewardKind: 'emblem',
    rewardId: 'emblem_garden',
    kind: 'hall_tier',
    target: 1,
    tierId: GUILD_HALL_TIER_GARDEN,
  },
  {
    id: 'gach_hall_arcana',
    name: 'Arcane corner',
    description: 'Build the Arcana station in the guild hall.',
    rewardKind: 'emblem',
    rewardId: 'emblem_arcana',
    kind: 'hall_tier',
    target: 1,
    tierId: GUILD_HALL_TIER_ARCANA,
  },
  {
    id: 'gach_hall_5',
    name: 'A hall fit for kings',
    description: 'Build tier 5 of the guild hall.',
    rewardKind: 'emblem',
    rewardId: 'emblem_cage',
    kind: 'hall_tier',
    target: 1,
    tierId: GUILD_HALL_TIER_CAGE,
  },
  {
    id: 'gach_gold_100k',
    name: 'Deep pockets',
    description: 'Put 100,000 gold into the guild hall as a guild.',
    rewardKind: 'emblem',
    rewardId: 'emblem_pockets',
    kind: 'gold',
    target: GUILD_ACHIEVEMENT_GOLD_100K,
  },
  {
    id: 'gach_gold_500k',
    name: 'Deeper pockets',
    description: 'Put 500,000 gold into the guild hall as a guild.',
    rewardKind: 'emblem',
    rewardId: 'emblem_deeper_pockets',
    kind: 'gold',
    target: GUILD_ACHIEVEMENT_GOLD_500K,
  },
  {
    id: 'gach_materials',
    name: 'Stocked vault',
    description: 'Use 100,000 materials building the guild hall.',
    rewardKind: 'border',
    rewardId: 'border_vault',
    kind: 'materials',
    target: GUILD_ACHIEVEMENT_MATERIALS,
  },
  {
    // Vari: Many hands rules stay unchanged (gold chip-in or hall material donate).
    id: 'gach_donors_10',
    name: 'Many hands',
    description: 'Have 10 different members chip in.',
    rewardKind: 'border',
    rewardId: 'border_hands',
    kind: 'donors',
    target: GUILD_ACHIEVEMENT_DONORS_10,
  },
  {
    id: 'gach_donors_25',
    name: 'More hands',
    description: 'Have 25 different members chip in.',
    rewardKind: 'border',
    rewardId: 'border_more_hands',
    kind: 'donors',
    target: GUILD_ACHIEVEMENT_DONORS_25,
  },
  {
    // Vari: stays unlocked after members leave (unlock-once).
    id: 'gach_rising_strength',
    name: 'Rising strength',
    description: 'Have 25 members reach total level 500.',
    rewardKind: 'border',
    rewardId: 'border_strength',
    kind: 'members_level',
    target: GUILD_ACHIEVEMENT_MEMBERS_AT_LEVEL,
  },
]

export const GUILD_ACHIEVEMENT_BY_ID: Readonly<Record<string, GuildAchievementDef>> = Object.fromEntries(
  GUILD_ACHIEVEMENTS.map((row) => [row.id, row]),
)

export const GUILD_BANNER_EMBLEM_IDS = GUILD_ACHIEVEMENTS.filter((row) => row.rewardKind === 'emblem').map(
  (row) => row.rewardId,
)

export const GUILD_BANNER_BORDER_IDS = GUILD_ACHIEVEMENTS.filter((row) => row.rewardKind === 'border').map(
  (row) => row.rewardId,
)

export type GuildAchievementSnapshot = {
  completedTiers: string[]
  goldContributed: number
  goldContributedBy: Record<string, number>
  donatedBy?: Record<string, boolean | number | string>
  membersAtLevel500: number
  /** achievement id → ISO unlocked_at */
  unlocked?: Record<string, string>
}

export type GuildAchievementProgress = {
  id: string
  name: string
  description: string
  current: number
  target: number
  unlocked: boolean
  unlockedAt: string | null
  rewardKind: GuildBannerRewardKind
  rewardId: string
}

export type GuildAchievementEvaluation = {
  newlyUnlocked: string[]
  unlocked: Record<string, string>
  progress: GuildAchievementProgress[]
}

export function guildMaySetBanner(role: string): boolean {
  return role === 'leader' || role === 'officer'
}

export const GUILD_BANNER_ROLE_REFUSAL = 'Only the guild leader or an officer can change the banner.'
export const GUILD_BANNER_COLOUR_REFUSAL = 'That colour is not on the banner palette.'
export const GUILD_BANNER_EMBLEM_REFUSAL = 'That emblem is not unlocked.'
export const GUILD_BANNER_BORDER_REFUSAL = 'That border is not unlocked.'

function isPaletteId(value: unknown): value is GuildBannerPaletteId {
  return typeof value === 'string' && (GUILD_BANNER_PALETTE as readonly string[]).includes(value)
}

export function guildDonorIds(snapshot: {
  goldContributedBy?: Record<string, number>
  donatedBy?: Record<string, boolean | number | string>
}): string[] {
  const ids = new Set<string>()
  for (const [id, amount] of Object.entries(snapshot.goldContributedBy ?? {})) {
    if (id && Number(amount) > 0) ids.add(id)
  }
  for (const [id, flag] of Object.entries(snapshot.donatedBy ?? {})) {
    if (!id) continue
    if (flag === true || flag === 'true' || Number(flag) > 0) ids.add(id)
  }
  return [...ids]
}

export function guildAchievementCurrent(def: GuildAchievementDef, snapshot: GuildAchievementSnapshot): number {
  switch (def.kind) {
    case 'hall_tier':
      return def.tierId && snapshot.completedTiers.includes(def.tierId) ? 1 : 0
    case 'gold':
      return Math.max(0, snapshot.goldContributed)
    case 'materials':
      return guildHallMaterialsSpent(snapshot.completedTiers)
    case 'donors':
      return guildDonorIds(snapshot).length
    case 'members_level':
      return Math.max(0, snapshot.membersAtLevel500)
  }
}

export function unlockedRewardIds(unlockedAchievementIds: Iterable<string>): {
  emblems: Set<string>
  borders: Set<string>
} {
  const emblems = new Set<string>()
  const borders = new Set<string>()
  for (const id of unlockedAchievementIds) {
    const def = GUILD_ACHIEVEMENT_BY_ID[id]
    if (!def) continue
    if (def.rewardKind === 'emblem') emblems.add(def.rewardId)
    else borders.add(def.rewardId)
  }
  return { emblems, borders }
}

export function evaluateGuildAchievements(
  snapshot: GuildAchievementSnapshot,
  nowIso: string,
): GuildAchievementEvaluation {
  const unlocked: Record<string, string> = { ...(snapshot.unlocked ?? {}) }
  const newlyUnlocked: string[] = []
  const progress: GuildAchievementProgress[] = []
  for (const def of GUILD_ACHIEVEMENTS) {
    const current = guildAchievementCurrent(def, snapshot)
    const already = unlocked[def.id]
    if (already == null && current >= def.target) {
      unlocked[def.id] = nowIso
      newlyUnlocked.push(def.id)
    }
    const unlockedAt = unlocked[def.id] ?? null
    progress.push({
      id: def.id,
      name: def.name,
      description: def.description,
      current,
      target: def.target,
      unlocked: unlockedAt != null,
      unlockedAt,
      rewardKind: def.rewardKind,
      rewardId: def.rewardId,
    })
  }
  return { newlyUnlocked, unlocked, progress }
}

/** Shape-only read for a stored banner. Unlock checks belong on set. */
export function readGuildBanner(raw: unknown): GuildBanner {
  const source = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {}
  const background = isPaletteId(source.background) ? source.background : DEFAULT_GUILD_BANNER.background
  const accent = isPaletteId(source.accent) ? source.accent : DEFAULT_GUILD_BANNER.accent
  const emblemRaw = source.emblem
  const borderRaw = source.border
  const emblem =
    typeof emblemRaw === 'string' && (GUILD_BANNER_EMBLEM_IDS as string[]).includes(emblemRaw)
      ? emblemRaw
      : null
  const border =
    typeof borderRaw === 'string' && (GUILD_BANNER_BORDER_IDS as string[]).includes(borderRaw)
      ? borderRaw
      : null
  return { background, accent, emblem, border }
}

export function normalizeGuildBanner(
  raw: unknown,
  unlockedAchievementIds: Iterable<string> = [],
): { ok: true; banner: GuildBanner } | { ok: false; reason: string } {
  const source = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {}
  const background = source.background ?? DEFAULT_GUILD_BANNER.background
  const accent = source.accent ?? DEFAULT_GUILD_BANNER.accent
  if (!isPaletteId(background) || !isPaletteId(accent)) {
    return { ok: false, reason: GUILD_BANNER_COLOUR_REFUSAL }
  }
  const emblem = source.emblem == null || source.emblem === '' ? null : source.emblem
  const border = source.border == null || source.border === '' ? null : source.border
  if (emblem != null && typeof emblem !== 'string') {
    return { ok: false, reason: GUILD_BANNER_EMBLEM_REFUSAL }
  }
  if (border != null && typeof border !== 'string') {
    return { ok: false, reason: GUILD_BANNER_BORDER_REFUSAL }
  }
  const rewards = unlockedRewardIds(unlockedAchievementIds)
  if (emblem != null) {
    if (!(GUILD_BANNER_EMBLEM_IDS as string[]).includes(emblem) || !rewards.emblems.has(emblem)) {
      return { ok: false, reason: GUILD_BANNER_EMBLEM_REFUSAL }
    }
  }
  if (border != null) {
    if (!(GUILD_BANNER_BORDER_IDS as string[]).includes(border) || !rewards.borders.has(border)) {
      return { ok: false, reason: GUILD_BANNER_BORDER_REFUSAL }
    }
  }
  return { ok: true, banner: { background, accent, emblem, border } }
}

export function defaultGuildBanner(): GuildBanner {
  return { ...DEFAULT_GUILD_BANNER }
}

/** Merge a donor into the hall ledger. Empty ids are ignored. */
export function withGuildHallDonor(
  donatedBy: Record<string, boolean>,
  userId: string | null | undefined,
): Record<string, boolean> {
  if (!userId) return donatedBy
  if (donatedBy[userId]) return donatedBy
  return { ...donatedBy, [userId]: true }
}
