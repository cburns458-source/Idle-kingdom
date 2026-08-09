import { useEffect, useMemo, useState } from 'react'
import { loadDatabase, type LoadedDatabase } from './game/data/loadDatabase'
import { loadOrCreateSave, writeSave } from './game/save/saveStore'
import type { PlayerSave } from './game/save/types'
import {
  CASTLE_MAP_ID,
  CAVE_ENTRANCE_ID,
  CAVE_MAP_ID,
  CASTLE_GATEWAY_ID,
  MAIN_MAP_ID,
} from './game/world/constants'
import {
  applyTravelArrival,
  canTravelTo,
  findConnection,
  resolveActiveMapId,
  stopPrimaryActivity,
  travelDurationMs,
} from './game/world/travel'
import { BottomNav, type AppScreen } from './ui/BottomNav'
import { InventoryStub, LogStub, SettingsStub } from './ui/StubScreens'
import { LocationView } from './ui/LocationView'
import { TopHud } from './ui/TopHud'
import { TravelOverlay } from './ui/TravelOverlay'
import { WorldMapView } from './ui/WorldMapView'
import './App.css'

type BootState =
  | { status: 'loading' }
  | { status: 'ready'; database: LoadedDatabase; save: PlayerSave; saveCreated: boolean }
  | { status: 'error'; message: string }

interface TravelState {
  toLocationId: string
  fromLocationId: string
  startedAt: number
  durationMs: number
}

export default function App() {
  const [boot, setBoot] = useState<BootState>({ status: 'loading' })
  const [screen, setScreen] = useState<AppScreen>('location')
  const [browseMapId, setBrowseMapId] = useState(MAIN_MAP_ID)
  const [selectedLocationId, setSelectedLocationId] = useState<string | null>(null)
  const [travel, setTravel] = useState<TravelState | null>(null)
  const [travelProgress, setTravelProgress] = useState(0)

  useEffect(() => {
    let cancelled = false

    async function bootGame() {
      try {
        const database = await loadDatabase()
        const { save, created } = loadOrCreateSave(database.source)
        if (!cancelled) {
          const location = database.launchIndexes.locationsById.get(save.currentLocationId)
          setBrowseMapId(location ? resolveActiveMapId(location) : MAIN_MAP_ID)
          setSelectedLocationId(save.currentLocationId)
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

  useEffect(() => {
    if (!travel || boot.status !== 'ready') return

    let frame = 0
    const tick = () => {
      const elapsed = Date.now() - travel.startedAt
      const progress = Math.min(1, elapsed / travel.durationMs)
      setTravelProgress(progress)
      if (progress >= 1) {
        setBoot((current) => {
          if (current.status !== 'ready') return current
          const arrived = applyTravelArrival(current.save, travel.toLocationId)
          const saved = writeSave(arrived)
          const location = current.database.launchIndexes.locationsById.get(saved.currentLocationId)
          setBrowseMapId(location ? resolveActiveMapId(location) : MAIN_MAP_ID)
          setSelectedLocationId(saved.currentLocationId)
          setScreen('location')
          return { ...current, save: saved, saveCreated: false }
        })
        setTravel(null)
        setTravelProgress(0)
        return
      }
      frame = window.requestAnimationFrame(tick)
    }

    frame = window.requestAnimationFrame(tick)
    return () => window.cancelAnimationFrame(frame)
  }, [travel, boot.status])

  const ready = boot.status === 'ready' ? boot : null

  const totalXp = useMemo(
    () => ready?.save.skills.reduce((sum, skill) => sum + skill.xp, 0) ?? 0,
    [ready?.save.skills],
  )

  if (boot.status === 'loading') {
    return (
      <div className="app-shell">
        <main className="portrait-frame">
          <section className="panel">
            <h1>Loading</h1>
            <p>Preparing local save and game data…</p>
          </section>
        </main>
      </div>
    )
  }

  if (boot.status === 'error' || !ready) {
    return (
      <div className="app-shell">
        <main className="portrait-frame">
          <section className="panel panel-error">
            <h1>Unable to start</h1>
            <p>{boot.status === 'error' ? boot.message : 'Unknown error'}</p>
          </section>
        </main>
      </div>
    )
  }

  const { database, save } = ready
  const location =
    database.launchIndexes.locationsById.get(save.currentLocationId) ??
    database.launch.Locations[0]
  const activity = save.currentActivityId
    ? database.launchIndexes.activitiesById.get(save.currentActivityId)
    : undefined
  const activityLabel = activity
    ? (activity['Contextual Name'] ?? activity['Internal Key'])
    : 'None'

  const fromLocation = database.launchIndexes.locationsById.get(
    travel?.fromLocationId ?? save.currentLocationId,
  )
  const toLocation = database.launchIndexes.locationsById.get(travel?.toLocationId ?? '')

  function updateSave(next: PlayerSave) {
    const saved = writeSave(next)
    setBoot((current) =>
      current.status === 'ready' ? { ...current, save: saved, saveCreated: false } : current,
    )
  }

  function beginTravel(destinationId: string) {
    if (travel) return
    if (
      !canTravelTo(database.launch, save.currentLocationId, destinationId, browseMapId)
    ) {
      return
    }
    const connection = findConnection(database.launch, save.currentLocationId, destinationId)
    setTravel({
      fromLocationId: save.currentLocationId,
      toLocationId: destinationId,
      startedAt: Date.now(),
      durationMs: travelDurationMs(connection),
    })
    setTravelProgress(0)
  }

  function startActivity(activityId: string) {
    updateSave({
      ...save,
      currentActivityId: activityId,
      activityStartedAt: new Date().toISOString(),
    })
  }

  function stopActivity() {
    updateSave(stopPrimaryActivity(save))
  }

  return (
    <div className="app-shell">
      <main className="portrait-frame" aria-label="Idle Kingdoms">
        <TopHud
          totalXp={totalXp}
          gold={save.gold}
          activityLabel={activityLabel}
          locationLabel={location['Display Name']}
        />

        <div className="screen-body">
          {screen === 'location' && (
            <LocationView
              indexes={database.launchIndexes}
              location={location}
              currentActivityId={save.currentActivityId}
              onStartActivity={startActivity}
              onStopActivity={stopActivity}
              onOpenMap={() => {
                setBrowseMapId(resolveActiveMapId(location))
                setSelectedLocationId(save.currentLocationId)
                setScreen('map')
              }}
              onOpenSubMap={() => {
                if (save.currentLocationId === CAVE_ENTRANCE_ID) setBrowseMapId(CAVE_MAP_ID)
                if (save.currentLocationId === CASTLE_GATEWAY_ID) setBrowseMapId(CASTLE_MAP_ID)
                setSelectedLocationId(save.currentLocationId)
                setScreen('map')
              }}
            />
          )}

          {screen === 'map' && (
            <WorldMapView
              db={database.launch}
              mapId={browseMapId}
              currentLocationId={save.currentLocationId}
              selectedLocationId={selectedLocationId}
              onSelect={setSelectedLocationId}
              onTravel={beginTravel}
              onShowWorldMap={() => setBrowseMapId(MAIN_MAP_ID)}
              travelDisabled={Boolean(travel)}
            />
          )}

          {screen === 'inventory' && <InventoryStub />}
          {screen === 'log' && <LogStub />}
          {screen === 'settings' && <SettingsStub />}
        </div>

        <BottomNav screen={screen} onChange={setScreen} mapDisabled={Boolean(travel)} />

        {travel && fromLocation && toLocation && (
          <TravelOverlay
            fromName={fromLocation['Display Name']}
            toName={toLocation['Display Name']}
            progress={travelProgress}
          />
        )}
      </main>
    </div>
  )
}
