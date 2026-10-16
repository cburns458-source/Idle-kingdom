export const GUILD_PERMISSION_ACTIONS = ['deposit', 'withdraw', 'move_up_for_grabs'] as const

export type GuildPermissionAction = (typeof GUILD_PERMISSION_ACTIONS)[number]

export const GUILD_PERMISSION_RANKS = ['leader', 'officer', 'veteran', 'member', 'recruit'] as const

export type GuildPermissionRank = (typeof GUILD_PERMISSION_RANKS)[number]

/** Ranks that may perform each action when a guild has not set its own table. */
export const DEFAULT_GUILD_PERMISSIONS: Record<GuildPermissionAction, GuildPermissionRank[]> = {
  deposit: ['leader', 'officer', 'veteran', 'member', 'recruit'],
  withdraw: ['leader', 'officer'],
  move_up_for_grabs: ['leader', 'officer'],
}

export type GuildPermissionTable = Record<GuildPermissionAction, string[]>

export function defaultGuildPermissionTable(): GuildPermissionTable {
  return {
    deposit: [...DEFAULT_GUILD_PERMISSIONS.deposit],
    withdraw: [...DEFAULT_GUILD_PERMISSIONS.withdraw],
    move_up_for_grabs: [...DEFAULT_GUILD_PERMISSIONS.move_up_for_grabs],
  }
}

export function normalizeGuildPermissionTable(raw: unknown): GuildPermissionTable {
  const defaults = defaultGuildPermissionTable()
  if (!raw || typeof raw !== 'object') return defaults
  const source = raw as Record<string, unknown>
  const next = defaultGuildPermissionTable()
  for (const action of GUILD_PERMISSION_ACTIONS) {
    const value = source[action]
    if (!Array.isArray(value)) continue
    const ranks = value.filter((entry): entry is string => typeof entry === 'string')
    next[action] = GUILD_PERMISSION_RANKS.filter((rank) => ranks.includes(rank))
  }
  return next
}

export const GUILD_BANK_TOTAL_LEVEL_REQUIRED = 200

export const GUILD_BANK_LEVEL_WITHDRAW_REFUSAL =
  'Reach total level 200 to withdraw from the guild bank.'

export const GUILD_BANK_LEVEL_TAKE_REFUSAL =
  'Reach total level 200 to take from Up for grabs.'

/**
 * One server-side check used by hall, bank, and settings commands.
 *
 * The leader always may. Everyone else reads the per-rank table the leader set.
 */
export function guildMay(
  role: string,
  action: GuildPermissionAction,
  table: GuildPermissionTable = defaultGuildPermissionTable(),
): boolean {
  if (role === 'leader') return true
  const allowed = table[action] ?? DEFAULT_GUILD_PERMISSIONS[action]
  return allowed.includes(role)
}

export function guildMayWithdrawAtLevel(totalLevel: number): boolean {
  return totalLevel >= GUILD_BANK_TOTAL_LEVEL_REQUIRED
}
