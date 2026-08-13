import { useEffect, useMemo, useState } from 'react'
import { playerPortraitAssetPath } from '../game/assets/playerAssets'
import type { LoadedDatabase } from '../game/data/loadDatabase'
import { getSession, isSignedIn } from '../game/multiplayer/auth'
import { citadelHubSummary, listCitadelVisitors } from '../game/multiplayer/citadel'
import { fetchLeaderboard } from '../game/multiplayer/leaderboards'
import type { ActivityPresence, MultiplayerBoardKey } from '../game/multiplayer/types'
import {
  boardOptions,
  citadelVisitorSubtitle,
  emptyBoardMessage,
  leaderboardRows,
  SIGN_IN_PROMPT,
  type LeaderboardRowView,
} from '../game/multiplayer/views'
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
    return <GuildView save={save} onChangeSave={onChangeSave ?? (() => undefined)} />
  }

  if (section === 'citadel') {
    return <CitadelSocialView />
  }

  return <LeaderboardsView database={database} />
}

function SignInPrompt({ title }: { title: string }) {
  return (
    <section className="panel menu-panel">
      <h1>{title}</h1>
      <p className="lead">{SIGN_IN_PROMPT}</p>
    </section>
  )
}

function CitadelSocialView() {
  const session = getSession()
  const [visitors, setVisitors] = useState<ActivityPresence[]>([])
  const summary = useMemo(() => citadelHubSummary(visitors.length), [visitors.length])

  useEffect(() => {
    if (!isSignedIn()) return
    function refresh() {
      setVisitors(listCitadelVisitors())
    }
    refresh()
    const timer = window.setInterval(refresh, 4000)
    return () => window.clearInterval(timer)
  }, [])

  if (!session) return <SignInPrompt title="Citadel" />

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
                <span className="muted tiny">{citadelVisitorSubtitle(visitor)}</span>
              </div>
            </li>
          ))}
          {visitors.length === 0 && (
            <li className="muted tiny">
              No visitors on the Plaza right now. Travel to The Citadel to meet others.
            </li>
          )}
        </ul>
      </div>
    </section>
  )
}

function LeaderboardsView({ database }: { database: LoadedDatabase }) {
  const session = getSession()
  const boards = useMemo(() => boardOptions(database.launch), [database.launch])
  const [boardKey, setBoardKey] = useState<MultiplayerBoardKey>('total_level')
  const [rows, setRows] = useState<LeaderboardRowView[]>([])

  useEffect(() => {
    if (!isSignedIn()) return
    void fetchLeaderboard(boardKey).then((entries) => setRows(leaderboardRows(entries)))
  }, [boardKey])

  if (!session) return <SignInPrompt title="Leaderboards" />

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
            {boards.map((board) => (
              <option key={board.key} value={board.key}>
                {board.label}
              </option>
            ))}
          </select>
        </label>
        <ul className="leaderboard-list">
          {rows.map((row) => (
            <li key={`${boardKey}-${row.entryId}`} className="leaderboard-row">
              <span className="guild-member-index">{row.rank}</span>
              {row.emblem ? (
                <GuildEmblemBadge emblem={row.emblem} />
              ) : (
                <span
                  className="social-portrait"
                  style={{ backgroundImage: `url(${playerPortraitAssetPath(row.appearance)})` }}
                  aria-hidden
                />
              )}
              <div className="guild-member-copy">
                <strong>{row.username}</strong>
                <span className="muted tiny">{row.subtitle}</span>
              </div>
              <span className="guild-member-level">{row.valueLabel}</span>
            </li>
          ))}
          {rows.length === 0 && <li className="muted tiny">{emptyBoardMessage(boardKey)}</li>}
        </ul>
      </div>
    </section>
  )
}
