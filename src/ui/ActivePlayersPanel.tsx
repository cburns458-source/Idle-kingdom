import { useEffect, useState } from 'react'
import { playerPortraitAssetPath } from '../game/assets/playerAssets'
import { isSignedIn } from '../game/multiplayer/auth'
import { dmPairKey } from '../game/multiplayer/types'
import { getSession } from '../game/multiplayer/auth'
import { listChatMessages, sendChatMessage } from '../game/multiplayer/chat'
import {
  getPublicProfile,
  listPeersAtActivity,
  publishActivityPresence,
  sendFriendRequest,
} from '../game/multiplayer/presence'
import type { ActivityPresence, PublicPlayerProfile } from '../game/multiplayer/types'
import type { PlayerSave } from '../game/save/types'

interface ActivePlayersPanelProps {
  save: PlayerSave
  skillNameForId: (skillId: string | null) => string
}

/** Sidebar list of peers on the same activity — does not interrupt activity UI. */
export function ActivePlayersPanel({ save, skillNameForId }: ActivePlayersPanelProps) {
  const [peers, setPeers] = useState<ActivityPresence[]>([])
  const [profile, setProfile] = useState<PublicPlayerProfile | null>(null)
  const [dmBody, setDmBody] = useState('')
  const [dmNotice, setDmNotice] = useState<string | null>(null)
  const session = getSession()

  useEffect(() => {
    if (!isSignedIn()) {
      setPeers([])
      return
    }
    publishActivityPresence(save)
    setPeers(listPeersAtActivity(save.currentLocationId, save.currentActivityId))
    const timer = window.setInterval(() => {
      publishActivityPresence(save)
      setPeers(listPeersAtActivity(save.currentLocationId, save.currentActivityId))
    }, 15_000)
    return () => window.clearInterval(timer)
  }, [
    save.currentLocationId,
    save.currentActivityId,
    save.appearance,
    save.characterName,
    save.cosmetics.equipped,
  ])

  if (!isSignedIn()) return null

  return (
    <aside className="active-players-panel" aria-label="Other active players">
      <h2>Nearby adventurers</h2>
      {peers.length === 0 ? (
        <p className="muted tiny">No other players on this activity right now.</p>
      ) : (
        <ul>
          {peers.map((peer) => (
            <li key={peer.userId}>
              <button
                type="button"
                className="active-player-row"
                onClick={() => setProfile(getPublicProfile(peer.userId))}
              >
                <span
                  className="social-portrait"
                  style={{ backgroundImage: `url(${playerPortraitAssetPath(peer.appearance)})` }}
                  aria-hidden
                />
                <span className="quest-log-copy">
                  <strong>{peer.username}</strong>
                  <span className="muted tiny">
                    {skillNameForId(peer.skillId)} {peer.skillLevel ?? '—'}
                    {peer.guildName ? ` · ${peer.guildName}` : ''}
                  </span>
                </span>
              </button>
            </li>
          ))}
        </ul>
      )}

      {profile && session && (
        <div className="public-profile-sheet" role="dialog" aria-label="Public profile">
          <button type="button" className="linkish" onClick={() => setProfile(null)}>
            Close
          </button>
          <div className="public-profile-header">
            <span
              className="social-portrait large"
              style={{ backgroundImage: `url(${playerPortraitAssetPath(profile.appearance)})` }}
              aria-hidden
            />
            <div>
              <strong>{profile.username}</strong>
              <p className="muted tiny">
                Total level {profile.totalLevel}
                {profile.guildName ? ` · ${profile.guildName}` : ''} ·{' '}
                {profile.achievementsUnlocked} achievements
              </p>
            </div>
          </div>
          {profile.publicSkills.length > 0 && (
            <ul className="muted tiny public-skill-list">
              {profile.publicSkills.slice(0, 8).map((skill) => (
                <li key={skill.skillId}>
                  {skillNameForId(skill.skillId)} {skill.level}
                </li>
              ))}
            </ul>
          )}
          <button
            type="button"
            className="btn secondary"
            onClick={() => {
              const result = sendFriendRequest(profile.userId)
              setDmNotice(result.ok ? 'Friend request sent.' : result.reason)
            }}
          >
            Friend request
          </button>
          <form
            onSubmit={(event) => {
              event.preventDefault()
              const pairKey = dmPairKey(session.userId, profile.userId)
              void sendChatMessage({ kind: 'dm', pairKey }, dmBody).then(async (result) => {
                if (!result.ok) {
                  setDmNotice(result.reason)
                  return
                }
                setDmBody('')
                setDmNotice('Message sent.')
                await listChatMessages({ kind: 'dm', pairKey })
              })
            }}
          >
            <input
              value={dmBody}
              onChange={(event) => setDmBody(event.target.value)}
              placeholder="Direct message…"
              aria-label="Direct message"
              maxLength={240}
            />
            <button type="submit">DM</button>
          </form>
          {dmNotice && <p className="muted tiny">{dmNotice}</p>}
        </div>
      )}
    </aside>
  )
}
