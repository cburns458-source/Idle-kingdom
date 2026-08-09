import { useEffect, useState } from 'react'
import { loadDatabase, type LoadedDatabase } from './game/data/loadDatabase'
import { loadOrCreateSave } from './game/save/saveStore'
import type { PlayerSave } from './game/save/types'
import './App.css'

type BootState =
  | { status: 'loading' }
  | { status: 'ready'; database: LoadedDatabase; save: PlayerSave; saveCreated: boolean }
  | { status: 'error'; message: string }

export default function App() {
  const [boot, setBoot] = useState<BootState>({ status: 'loading' })

  useEffect(() => {
    let cancelled = false

    async function bootGame() {
      try {
        const database = await loadDatabase()
        const { save, created } = loadOrCreateSave(database.source)
        if (!cancelled) {
          setBoot({
            status: 'ready',
            database,
            save,
            saveCreated: created,
          })
        }
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Unknown boot failure'
        if (!cancelled) {
          setBoot({ status: 'error', message })
        }
      }
    }

    void bootGame()
    return () => {
      cancelled = true
    }
  }, [])

  return (
    <div className="app-shell">
      <main className="portrait-frame" aria-label="Idle Kingdoms">
        <header className="top-hud">
          <p className="brand">Idle Kingdoms</p>
          <p className="hud-meta">Single-player demo</p>
        </header>

        {boot.status === 'loading' && (
          <section className="panel">
            <h1>Loading</h1>
            <p>Preparing local save and game data…</p>
          </section>
        )}

        {boot.status === 'error' && (
          <section className="panel panel-error">
            <h1>Unable to start</h1>
            <p>{boot.message}</p>
          </section>
        )}

        {boot.status === 'ready' && <ReadyPanel boot={boot} />}
      </main>
    </div>
  )
}

function ReadyPanel({
  boot,
}: {
  boot: Extract<BootState, { status: 'ready' }>
}) {
  const location = boot.database.launchIndexes.locationsById.get(boot.save.currentLocationId)
  const locationName = location?.['Display Name'] ?? boot.save.currentLocationId
  const launchLocationCount = boot.database.launch.Locations.length
  const sourceLocationCount = boot.database.source.Locations.length

  return (
    <>
      <section className="panel">
        <h1>{locationName}</h1>
        <p className="lead">
          {boot.saveCreated
            ? 'A new local save was created automatically.'
            : 'Your existing local save was loaded.'}
        </p>
        <dl className="stat-list">
          <div>
            <dt>Gold</dt>
            <dd>{boot.save.gold}</dd>
          </div>
          <div>
            <dt>Inventory items</dt>
            <dd>{boot.save.inventory.length}</dd>
          </div>
          <div>
            <dt>Skills tracked</dt>
            <dd>{boot.save.skills.length}</dd>
          </div>
          <div>
            <dt>Save version</dt>
            <dd>{boot.save.saveVersion}</dd>
          </div>
        </dl>
      </section>

      <section className="panel panel-quiet">
        <h2>Data diagnostics</h2>
        <ul className="diag-list">
          <li>Source tables loaded with no validation errors.</li>
          <li>
            Locations: {launchLocationCount} Launch / {sourceLocationCount} source.
          </li>
          <li>Needs Data rows deferred: {boot.database.needsDataCount}.</li>
          <li>No login required.</li>
        </ul>
      </section>
    </>
  )
}
