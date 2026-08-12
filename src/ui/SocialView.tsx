import { useEffect, useMemo, useState } from 'react'
import { playerPortraitAssetPath } from '../game/assets/playerAssets'
import type { LoadedDatabase } from '../game/data/loadDatabase'
import { getSession, isSignedIn } from '../game/multiplayer/auth'
import {
  boardLabel,
  fetchLeaderboard,
  launchBoardKeys,
} from '../game/multiplayer/leaderboards'
import type { LeaderboardEntry, MultiplayerBoardKey } from '../game/multiplayer/types'
import type { PlayerSave } from '../game/save/types'
import { GuildView } from './GuildView'

export type SocialSection = 'leaderboards' | 'guilds'

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

  return <LeaderboardsView save={save} database={database} />
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
