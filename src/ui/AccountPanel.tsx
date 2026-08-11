import { useState } from 'react'
import type { GameDatabase } from '../game/data/types'
import {
  getSession,
  signInWithMagicLink,
  signInWithPassword,
  signOut,
  signUpWithPassword,
} from '../game/multiplayer/auth'
import { multiplayerMode } from '../game/multiplayer/client'
import { pullCloudSave, pushCloudSave } from '../game/multiplayer/cloudSave'
import { clearActivityPresence } from '../game/multiplayer/presence'
import type { PlayerSave } from '../game/save/types'
import { writeSave } from '../game/save/saveStore'

interface AccountPanelProps {
  db: GameDatabase
  save: PlayerSave
  onChangeSave: (save: PlayerSave) => void
  onOpenSocial: () => void
  onMessage: (message: string) => void
  onAuthChanged?: () => void
}

export function AccountPanel({
  db,
  save,
  onChangeSave,
  onOpenSocial,
  onMessage,
  onAuthChanged,
}: AccountPanelProps) {
  const [email, setEmail] = useState('')
  const [username, setUsername] = useState(save.characterName ?? '')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [authTick, setAuthTick] = useState(0)
  const session = getSession()
  const mode = multiplayerMode()
  void authTick

  async function run(action: () => Promise<void>) {
    setBusy(true)
    try {
      await action()
      setAuthTick((value) => value + 1)
      onAuthChanged?.()
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="menu-demo-block account-panel">
      <p className="muted tiny">Account</p>
      <p className="muted tiny">
        Optional multiplayer ({mode === 'local' ? 'local demo backend' : 'Supabase'}). Offline play
        stays intact.
      </p>
      {session ? (
        <>
          <p className="lead">Signed in as {session.username}</p>
          <p className="muted tiny">{session.email}</p>
          <button
            type="button"
            className="btn secondary"
            disabled={busy}
            onClick={() =>
              void run(async () => {
                const result = await pushCloudSave(db, save)
                onMessage(result.ok ? 'Cloud save uploaded.' : result.reason)
              })
            }
          >
            Sync cloud save
          </button>
          <button
            type="button"
            className="btn secondary"
            disabled={busy}
            onClick={() =>
              void run(async () => {
                const result = await pullCloudSave()
                if (!result.ok) {
                  onMessage(result.reason)
                  return
                }
                onChangeSave(writeSave(result.save))
                onMessage('Cloud save loaded onto this device.')
              })
            }
          >
            Load cloud save
          </button>
          <button type="button" className="btn secondary" onClick={onOpenSocial}>
            Open Social
          </button>
          <button
            type="button"
            className="btn secondary"
            disabled={busy}
            onClick={() =>
              void run(async () => {
                await pushCloudSave(db, save)
                clearActivityPresence()
                await signOut()
                onMessage('Signed out. Local save remains on this device.')
              })
            }
          >
            Sign out
          </button>
        </>
      ) : (
        <>
          <label className="field-label">
            Email
            <input
              className="text-input"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              autoComplete="email"
            />
          </label>
          <label className="field-label">
            Username
            <input
              className="text-input"
              value={username}
              onChange={(event) => setUsername(event.target.value)}
              autoComplete="username"
            />
          </label>
          <label className="field-label">
            Password
            <input
              className="text-input"
              type="password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              autoComplete="current-password"
            />
          </label>
          <button
            type="button"
            className="btn secondary"
            disabled={busy || !email || !password}
            onClick={() =>
              void run(async () => {
                const result = await signInWithPassword(email, password)
                onMessage(result.ok ? `Welcome back, ${result.session.username}.` : result.reason)
              })
            }
          >
            Sign in
          </button>
          <button
            type="button"
            className="btn secondary"
            disabled={busy}
            onClick={() =>
              void run(async () => {
                const result = await signUpWithPassword(email, username || 'Adventurer', password)
                if (result.ok) {
                  await pushCloudSave(db, {
                    ...save,
                    characterName: save.characterName ?? result.session.username,
                  })
                }
                onMessage(result.ok ? `Account created for ${result.session.username}.` : result.reason)
              })
            }
          >
            Create account
          </button>
          {mode === 'supabase' && (
            <button
              type="button"
              className="btn secondary"
              disabled={busy || !email}
              onClick={() =>
                void run(async () => {
                  const result = await signInWithMagicLink(email)
                  onMessage(result.ok ? 'Magic link sent.' : result.reason)
                })
              }
            >
              Email magic link
            </button>
          )}
        </>
      )}
    </div>
  )
}
