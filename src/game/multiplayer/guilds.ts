import { getSession } from './auth'
import { getLocalBackend, multiplayerMode } from './client'
import type {
  CreateGuildInput,
  GuildApplication,
  GuildChallenge,
  GuildEmblem,
  GuildJoinPolicy,
  GuildMember,
  GuildProject,
  GuildRankKey,
  GuildRecord,
  GuildRole,
} from './types'

export async function createGuild(
  input: CreateGuildInput,
  goldAvailable: number,
): Promise<
  { ok: true; guild: GuildRecord; goldCost: number } | { ok: false; reason: string }
> {
  const session = getSession()
  if (!session) return { ok: false, reason: 'Sign in to create a guild.' }
  // Remote path reuses local semantics via edge functions later; local demo first.
  void multiplayerMode()
  return getLocalBackend().createGuild(session, input, goldAvailable)
}

export async function listGuilds(): Promise<Array<GuildRecord & { memberCount: number }>> {
  return getLocalBackend().listGuilds()
}

export async function getGuild(guildId: string): Promise<GuildRecord | null> {
  return getLocalBackend().getGuild(guildId)
}

export async function listGuildMembers(guildId: string): Promise<GuildMember[]> {
  return getLocalBackend().guildMembers(guildId)
}

export async function applyToGuild(
  guildId: string,
  message: string,
): Promise<{ ok: true; joined: boolean } | { ok: false; reason: string }> {
  const session = getSession()
  if (!session) return { ok: false, reason: 'Sign in to apply.' }
  return getLocalBackend().applyToGuild(session, guildId, message)
}

export async function listGuildApplications(guildId: string): Promise<GuildApplication[]> {
  return getLocalBackend().listApplications(guildId)
}

export async function decideGuildApplication(
  applicationId: string,
  accept: boolean,
): Promise<{ ok: true } | { ok: false; reason: string }> {
  const session = getSession()
  if (!session) return { ok: false, reason: 'Sign in required.' }
  return getLocalBackend().decideApplication(session.userId, applicationId, accept)
}

export async function setGuildMemberRole(
  guildId: string,
  targetUserId: string,
  role: GuildRole,
): Promise<{ ok: true } | { ok: false; reason: string }> {
  const session = getSession()
  if (!session) return { ok: false, reason: 'Sign in required.' }
  return getLocalBackend().setMemberRole(session.userId, guildId, targetUserId, role)
}

export async function setGuildJoinPolicy(
  guildId: string,
  joinPolicy: GuildJoinPolicy,
): Promise<{ ok: true } | { ok: false; reason: string }> {
  const session = getSession()
  if (!session) return { ok: false, reason: 'Sign in required.' }
  return getLocalBackend().setGuildJoinPolicy(session.userId, guildId, joinPolicy)
}

export async function setGuildRankLabels(
  guildId: string,
  rankLabels: Partial<Record<GuildRankKey, string>>,
): Promise<{ ok: true } | { ok: false; reason: string }> {
  const session = getSession()
  if (!session) return { ok: false, reason: 'Sign in required.' }
  return getLocalBackend().setGuildRankLabels(session.userId, guildId, rankLabels)
}

export async function setGuildEmblem(
  guildId: string,
  emblem: GuildEmblem,
): Promise<{ ok: true } | { ok: false; reason: string }> {
  const session = getSession()
  if (!session) return { ok: false, reason: 'Sign in required.' }
  return getLocalBackend().setGuildEmblem(session.userId, guildId, emblem)
}

export async function leaveGuild(): Promise<{ ok: true } | { ok: false; reason: string }> {
  const session = getSession()
  if (!session) return { ok: false, reason: 'Sign in required.' }
  return getLocalBackend().leaveGuild(session.userId)
}

export async function contributeGuildProject(
  projectId: string,
  amount: number,
): Promise<{ ok: true; project: GuildProject } | { ok: false; reason: string }> {
  const session = getSession()
  if (!session) return { ok: false, reason: 'Sign in required.' }
  return getLocalBackend().contributeToProject(session.userId, projectId, amount)
}

export async function listGuildProjects(guildId: string): Promise<GuildProject[]> {
  return getLocalBackend().guildProjects(guildId)
}

export async function listGuildChallenges(guildId: string): Promise<GuildChallenge[]> {
  getLocalBackend().refreshGuildChallengeAggregates(guildId)
  return getLocalBackend().guildChallenges(guildId)
}

export function currentGuildId(): string | null {
  const session = getSession()
  if (!session) return null
  return getLocalBackend().getProfile(session.userId)?.guildId ?? null
}

export function guildRoleLabel(guild: GuildRecord, role: GuildRole): string {
  return guild.rankLabels[role] ?? role
}
