import { useEffect, useMemo, useState } from 'react'
import { playerPortraitAssetPath } from '../game/assets/playerAssets'
import type { LoadedDatabase } from '../game/data/loadDatabase'
import { getSession, isSignedIn } from '../game/multiplayer/auth'
import {
  applyToGuild,
  contributeGuildProject,
  createGuild,
  currentGuildId,
  decideGuildApplication,
  leaveGuild,
  listGuildApplications,
  listGuildChallenges,
  listGuildMembers,
  listGuildProjects,
  listGuilds,
  setGuildMemberRole,
} from '../game/multiplayer/guilds'
import {
  boardLabel,
  fetchLeaderboard,
  launchBoardKeys,
} from '../game/multiplayer/leaderboards'
import type {
  GuildApplication,
  GuildChallenge,
  GuildMember,
  GuildProject,
  GuildRecord,
  LeaderboardEntry,
  MultiplayerBoardKey,
} from '../game/multiplayer/types'
import type { PlayerSave } from '../game/save/types'

export type SocialSection = 'leaderboards' | 'guilds'

interface SocialViewProps {
  save: PlayerSave
  database: LoadedDatabase
  section: SocialSection
}

export function SocialView({ save, database, section }: SocialViewProps) {
  const session = getSession()
  const boardKeys = useMemo(() => launchBoardKeys(database.launch), [database.launch])
  const [boardKey, setBoardKey] = useState<MultiplayerBoardKey>('total_level')
  const [entries, setEntries] = useState<LeaderboardEntry[]>([])
  const [guilds, setGuilds] = useState<GuildRecord[]>([])
  const [members, setMembers] = useState<GuildMember[]>([])
  const [applications, setApplications] = useState<GuildApplication[]>([])
  const [projects, setProjects] = useState<GuildProject[]>([])
  const [challenges, setChallenges] = useState<GuildChallenge[]>([])
  const [guildName, setGuildName] = useState('')
  const [guildDescription, setGuildDescription] = useState('')
  const [notice, setNotice] = useState<string | null>(null)
  const guildId = currentGuildId()

  useEffect(() => {
    if (!isSignedIn() || section !== 'leaderboards') return
    void fetchLeaderboard(boardKey).then(setEntries)
  }, [boardKey, section])

  useEffect(() => {
    if (!isSignedIn() || section !== 'guilds') return
    void (async () => {
      setGuilds(await listGuilds())
      if (guildId) {
        setMembers(await listGuildMembers(guildId))
        setApplications(await listGuildApplications(guildId))
        setProjects(await listGuildProjects(guildId))
        setChallenges(await listGuildChallenges(guildId))
      } else {
        setMembers([])
        setApplications([])
        setProjects([])
        setChallenges([])
      }
    })()
  }, [section, guildId, notice])

  if (!session) {
    return (
      <section className="panel menu-panel">
        <h1>{section === 'guilds' ? 'Guilds' : 'Leaderboards'}</h1>
        <p className="lead">Sign in from Menu → Account to use multiplayer features.</p>
      </section>
    )
  }

  if (section === 'leaderboards') {
    return (
      <section className="panel menu-panel social-panel">
        <h1>Leaderboards</h1>
        <p className="muted tiny">Signed in as {session.username}</p>
        <div className="menu-tab-panel">
          <label className="field-label">
            Board
            <select
              value={boardKey}
              onChange={(event) => setBoardKey(event.target.value as MultiplayerBoardKey)}
            >
              {boardKeys.map((key) => (
                <option key={key} value={key}>
                  {boardLabel(database.launch, key)}
                </option>
              ))}
            </select>
          </label>
          <ul className="achievement-list social-leaderboard-list">
            {entries.map((entry) => (
              <li key={`${entry.boardKey}-${entry.userId}`}>
                <span className="muted tiny">#{entry.rank}</span>
                <span
                  className="social-portrait"
                  style={{ backgroundImage: `url(${playerPortraitAssetPath(entry.appearance)})` }}
                  aria-hidden
                />
                <div className="quest-log-copy">
                  <strong>{entry.username}</strong>
                  <span className="muted tiny">
                    {entry.guildName ? entry.guildName : 'No guild'} ·{' '}
                    {entry.value.toLocaleString()}
                  </span>
                </div>
              </li>
            ))}
            {entries.length === 0 && (
              <li className="muted tiny">No scores yet — sync a cloud save to submit.</li>
            )}
          </ul>
        </div>
      </section>
    )
  }

  return (
    <section className="panel menu-panel social-panel">
      <h1>Guilds</h1>
      <p className="muted tiny">Signed in as {session.username}</p>
      <div className="menu-tab-panel">
        {!guildId && (
          <>
            <p className="lead">Create or apply to a guild. Rewards are cosmetic / recognition only.</p>
            <form
              className="guild-create-form"
              onSubmit={(event) => {
                event.preventDefault()
                void createGuild(guildName, guildDescription).then((result) => {
                  setNotice(result.ok ? `Created ${result.guild.name}.` : result.reason)
                  if (result.ok) {
                    setGuildName('')
                    setGuildDescription('')
                  }
                })
              }}
            >
              <input
                value={guildName}
                onChange={(event) => setGuildName(event.target.value)}
                placeholder="Guild name"
                aria-label="Guild name"
              />
              <input
                value={guildDescription}
                onChange={(event) => setGuildDescription(event.target.value)}
                placeholder="Description"
                aria-label="Guild description"
              />
              <button type="submit">Create guild</button>
            </form>
            <ul className="achievement-list">
              {guilds.map((guild) => (
                <li key={guild.id}>
                  <div className="quest-log-copy">
                    <strong>
                      {guild.emblem} {guild.name}
                    </strong>
                    <span className="muted tiny">{guild.description || 'No description.'}</span>
                  </div>
                  <button
                    type="button"
                    onClick={() =>
                      void applyToGuild(guild.id, `${save.characterName ?? 'Adventurer'} applies`).then(
                        (result) => setNotice(result.ok ? 'Application sent.' : result.reason),
                      )
                    }
                  >
                    Apply
                  </button>
                </li>
              ))}
            </ul>
          </>
        )}

        {guildId && (
          <>
            <p className="lead">Your guild roster, projects, and challenges.</p>
            <ul className="achievement-list">
              {members.map((member) => (
                <li key={member.userId}>
                  <div className="quest-log-copy">
                    <strong>{member.username}</strong>
                    <span className="muted tiny">{member.role}</span>
                  </div>
                  {member.role !== 'leader' && (
                    <button
                      type="button"
                      onClick={() =>
                        void setGuildMemberRole(
                          guildId,
                          member.userId,
                          member.role === 'officer' ? 'member' : 'officer',
                        ).then((result) =>
                          setNotice(result.ok ? 'Role updated.' : result.reason),
                        )
                      }
                    >
                      Toggle officer
                    </button>
                  )}
                </li>
              ))}
            </ul>
            {applications.length > 0 && (
              <>
                <h2 className="menu-section-heading">Applications</h2>
                <ul className="achievement-list">
                  {applications.map((application) => (
                    <li key={application.id}>
                      <div className="quest-log-copy">
                        <strong>{application.username}</strong>
                        <span className="muted tiny">{application.message}</span>
                      </div>
                      <button
                        type="button"
                        onClick={() =>
                          void decideGuildApplication(application.id, true).then((result) =>
                            setNotice(result.ok ? 'Accepted.' : result.reason),
                          )
                        }
                      >
                        Accept
                      </button>
                    </li>
                  ))}
                </ul>
              </>
            )}
            <h2 className="menu-section-heading">Contribution projects</h2>
            <ul className="achievement-list">
              {projects.map((project) => (
                <li key={project.id}>
                  <div className="quest-log-copy">
                    <strong>{project.name}</strong>
                    <span className="muted tiny">
                      {project.contributed}/{project.goalAmount} · {project.rewardLabel}
                    </span>
                  </div>
                  <button
                    type="button"
                    onClick={() =>
                      void contributeGuildProject(project.id, 10).then((result) =>
                        setNotice(result.ok ? 'Contributed 10.' : result.reason),
                      )
                    }
                  >
                    +10
                  </button>
                </li>
              ))}
            </ul>
            <h2 className="menu-section-heading">Challenges</h2>
            <ul className="achievement-list">
              {challenges.map((challenge) => (
                <li key={challenge.id}>
                  <div className="quest-log-copy">
                    <strong>{challenge.name}</strong>
                    <span className="muted tiny">
                      {challenge.currentValue}/{challenge.goalValue}
                    </span>
                  </div>
                </li>
              ))}
            </ul>
            <button
              type="button"
              onClick={() =>
                void leaveGuild().then((result) =>
                  setNotice(result.ok ? 'Left guild.' : result.reason),
                )
              }
            >
              Leave guild
            </button>
          </>
        )}
        {notice && <p className="muted tiny">{notice}</p>}
      </div>
    </section>
  )
}
