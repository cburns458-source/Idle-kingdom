import { getSession } from './auth'
import { getLocalBackend, multiplayerMode } from './client'
import type {
  GuildApplication,
  GuildChallenge,
  GuildMember,
  GuildProject,
  GuildRecord,
  GuildRole,
} from './types'

export async function createGuild(
  name: string,
  description: string,
  emblem?: string,
): Promise<{ ok: true; guild: GuildRecord } | { ok: false; reason: string }> {
  const session = getSession()
  if (!session) return { ok: false, reason: 'Sign in to create a guild.' }
  if (multiplayerMode() !== 'local') {
    // Remote path reuses local semantics via edge functions later; local demo first.
    return getLocalBackend().createGuild(session, name, description, emblem)
  }
  return getLocalBackend().createGuild(session, name, description, emblem)
}

export async function listGuilds(): Promise<GuildRecord[]> {
  return getLocalBackend().listGuilds()
}

export async function listGuildMembers(guildId: string): Promise<GuildMember[]> {
  return getLocalBackend().guildMembers(guildId)
}

export async function applyToGuild(
  guildId: string,
  message: string,
): Promise<{ ok: true } | { ok: false; reason: string }> {
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
