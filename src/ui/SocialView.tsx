import { useEffect, useMemo, useState } from 'react'
import { playerPortraitAssetPath } from '../game/assets/playerAssets'
import type { LoadedDatabase } from '../game/data/loadDatabase'
import { getSession, isSignedIn } from '../game/multiplayer/auth'
import { citadelHubSummary, listCitadelVisitors } from '../game/multiplayer/citadel'
import {
  boardLabel,
  fetchLeaderboard,
  launchBoardKeys,
} from '../game/multiplayer/leaderboards'
import type { ActivityPresence, LeaderboardEntry, MultiplayerBoardKey } from '../game/multiplayer/types'
import type { PlayerSave } from '../game/save/types'
import { GuildEmblemBadge } from './guildEmblemIcons'
import { GuildView } from './GuildView'

export type SocialSection = 'leaderboards' | 'guilds' | 'citadel'

interface SocialViewProps {
  save: PlayerSave
  database: LoadedDatabase
  section: SocialSection
  onChangeSave?: (save: PlayerSave) => void
}

export function SocialView({ save, database, section, onChangeSave }: SocialViewProps) {
  if (section === 'guilds') {
    return (
      <GuildView
        save={save}
        onChangeSave={onChangeSave ?? (() => undefined)}
      />
    )
  }

  if (section === 'citadel') {
    return <CitadelSocialView />
  }

  return <LeaderboardsView save={save} database={database} />
}

function CitadelSocialView() {
  const session = getSession()
  const [visitors, setVisitors] = useState<ActivityPresence[]>([])
  const summary = useMemo(() => citadelHubSummary(), [visitors.length])

  useEffect(() => {
    if (!isSignedIn()) return
    function refresh() {
      setVisitors(listCitadelVisitors())
    }
    refresh()
    const timer = window.setInterval(refresh, 4000)
    return () => window.clearInterval(timer)
  }, [])

  if (!session) {
    return (
      <section className="panel menu-panel">
        <h1>Citadel</h1>
        <p className="lead">Sign in from Menu → Account to use multiplayer features.</p>
      </section>
    )
  }

  return (
    <section className="panel menu-panel social-panel">
      <h1>Citadel</h1>
      <p className="muted tiny">Signed in as {session.username}</p>
      <div className="menu-tab-panel">
        <p className="lead">{summary.note}</p>
        <p className="muted tiny">
          Plaza presence: {summary.visitorCount} · Chat channel: {summary.chatChannel}
        </p>
        <ul className="leaderboard-list">
          {visitors.map((visitor) => (
            <li key={visitor.userId} className="leaderboard-row">
              <span
                className="social-portrait"
                style={{ backgroundImage: `url(${playerPortraitAssetPath(visitor.appearance)})` }}
                aria-hidden
              />
              <div className="guild-member-copy">
                <strong>{visitor.username}</strong>
                <span className="muted tiny">
                  {visitor.guildName ?? 'No guild'}
                  {visitor.skillLevel != null ? ` · Lv ${visitor.skillLevel}` : ''}
                </span>
              </div>
            </li>
          ))}
          {visitors.length === 0 && (
            <li className="muted tiny">No visitors on the Plaza right now. Travel to The Citadel to meet others.</li>
          )}
        </ul>
      </div>
    </section>
  )
}

function LeaderboardsView({
  save: _save,
  database,
}: {
  save: PlayerSave
  database: LoadedDatabase
}) {
  const session = getSession()
  const boardKeys = useMemo(() => launchBoardKeys(database.launch), [database.launch])
  const [boardKey, setBoardKey] = useState<MultiplayerBoardKey>('total_level')
  const [entries, setEntries] = useState<LeaderboardEntry[]>([])

  useEffect(() => {
    if (!isSignedIn()) return
    void fetchLeaderboard(boardKey).then(setEntries)
  }, [boardKey])

  if (!session) {
    return (
      <section className="panel menu-panel">
        <h1>Leaderboards</h1>
        <p className="lead">Sign in from Menu → Account to use multiplayer features.</p>
      </section>
    )
  }

  return (
    <section className="panel menu-panel social-panel">
      <h1>Leaderboards</h1>
      <p className="muted tiny">Signed in as {session.username}</p>
      <div className="menu-tab-panel">
        <label className="field-label">
          Board
          <select
            className="text-input"
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
        <ul className="leaderboard-list">
          {entries.map((entry) => (
            <li key={`${entry.boardKey}-${entry.userId}`} className="leaderboard-row">
              <span className="guild-member-index">{entry.rank}</span>
              {entry.entryKind === 'guild' && entry.emblem ? (
                <GuildEmblemBadge emblem={entry.emblem} />
              ) : (
                <span
                  className="social-portrait"
                  style={{ backgroundImage: `url(${playerPortraitAssetPath(entry.appearance)})` }}
                  aria-hidden
                />
              )}
              <div className="guild-member-copy">
                <strong>{entry.username}</strong>
                <span className="muted tiny">
                  {entry.entryKind === 'guild'
                    ? entry.guildName ?? 'Guild'
                    : entry.guildName
                      ? entry.guildName
                      : 'No guild'}
                </span>
              </div>
              <span className="guild-member-level">{entry.value.toLocaleString()}</span>
            </li>
          ))}
          {entries.length === 0 && (
            <li className="muted tiny">
              {boardKey === 'guild_total_level'
                ? 'No guilds yet — create or join one from the Guilds tab.'
                : 'No scores yet — sync a cloud save to submit.'}
            </li>
          )}
        </ul>
      </div>
    </section>
  )
}
