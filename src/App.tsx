import { useEffect, useMemo, useRef, useState } from 'react'
import {
  activityStillValid,
  beginActivitySave,
  clearActivitySave,
  completeGatheringAction,
  generateNextAction,
  restoreActiveActionState,
  validateActivityStart,
} from './game/activity/engine'
import type { LootGrant } from './game/activity/types'
import { loadDatabase, type LoadedDatabase } from './game/data/loadDatabase'
import type { ActivityRow } from './game/data/types'
import { loadOrCreateSave, writeSave } from './game/save/saveStore'
import type { PlayerSave } from './game/save/types'
import {
  CASTLE_GATEWAY_ID,
  CASTLE_MAP_ID,
  CAVE_ENTRANCE_ID,
  CAVE_MAP_ID,
  MAIN_MAP_ID,
} from './game/world/constants'
import {
  applyTravelArrival,
  canTravelTo,
  findConnection,
  resolveActiveMapId,
  travelDurationMs,
} from './game/world/travel'
import { ActivityPanel } from './ui/ActivityPanel'
import { BottomNav, type AppScreen } from './ui/BottomNav'
import { LogStub, SettingsStub } from './ui/StubScreens'
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
  const [actionProgress, setActionProgress] = useState(0)
  const [activityError, setActivityError] = useState<string | null>(null)
  const [recentLoot, setRecentLoot] = useState<LootGrant[]>([])
  const [lastMessage, setLastMessage] = useState<string | null>(null)
  const bootRef = useRef(boot)
  bootRef.current = boot

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
          setActionProgress(0)
          setLastMessage(null)
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

  // Ensure an action exists while an activity is running.
  useEffect(() => {
    if (boot.status !== 'ready' || travel) return
    const { database, save } = boot
    if (!save.currentActivityId || save.currentActionId) return

    if (!activityStillValid(database.launch, save, save.currentActivityId)) {
      const stopped = writeSave(clearActivitySave(save))
      setBoot({ ...boot, save: stopped, saveCreated: false })
      setActivityError('Activity stopped — requirements are no longer met.')
      return
    }

    const generated = generateNextAction(database.launch, save, save.currentActivityId)
    if (!generated) {
      const stopped = writeSave(clearActivitySave(save))
      setBoot({ ...boot, save: stopped, saveCreated: false })
      setActivityError('No gatherable actions remain for this activity.')
      return
    }
    setBoot({ ...boot, save: writeSave(generated.save), saveCreated: false })
  }, [boot, travel])

  // Progress + complete the current gathering action.
  useEffect(() => {
    if (boot.status !== 'ready' || travel) return
    const save = boot.save
    const actionState = restoreActiveActionState(save)
    if (!save.currentActivityId || !actionState) {
      setActionProgress(0)
      return
    }

    let frame = 0
    let completed = false

    const tick = () => {
      const elapsed = Date.now() - actionState.startedAtMs
      const progress = Math.min(1, elapsed / Math.max(1, actionState.durationMs))
      setActionProgress(progress)
      if (progress < 1) {
        frame = window.requestAnimationFrame(tick)
        return
      }
      if (completed) return
      completed = true

      const current = bootRef.current
      if (current.status !== 'ready' || !current.save.currentActivityId) return

      const action = current.database.launchIndexes.actionsById.get(actionState.actionId)
      if (!action) {
        const stopped = writeSave(clearActivitySave(current.save))
        setBoot({ ...current, save: stopped, saveCreated: false })
        return
      }

      const finished = completeGatheringAction(current.database.launch, current.save, action)
      let nextSave = finished.save
      const skillName =
        current.database.launchIndexes.skillsById.get(finished.result.skillId)?.['Display Name'] ??
        'Skill'
      const lootText = finished.result.loot
        .map((loot) => `+${loot.quantity} ${loot.displayName}`)
        .join(', ')
      setRecentLoot((prev) => [...finished.result.loot, ...prev].slice(0, 8))
      setLastMessage(
        [
          `${finished.result.actionName} complete`,
          finished.result.xpGained > 0 ? `+${finished.result.xpGained} ${skillName} XP` : null,
          lootText || null,
          finished.result.leveledUpTo ? `Reached level ${finished.result.leveledUpTo}` : null,
        ]
          .filter(Boolean)
          .join(' · '),
      )

      const activityId = current.save.currentActivityId
      if (!activityStillValid(current.database.launch, nextSave, activityId)) {
        nextSave = clearActivitySave(nextSave)
        setActivityError('Activity stopped — requirements are no longer met.')
        setActionProgress(0)
        setBoot({ ...current, save: writeSave(nextSave), saveCreated: false })
        return
      }

      const generated = generateNextAction(current.database.launch, nextSave, activityId)
      if (!generated) {
        setBoot({
          ...current,
          save: writeSave(clearActivitySave(nextSave)),
          saveCreated: false,
        })
        setActionProgress(0)
        return
      }

      setActionProgress(0)
      setBoot({ ...current, save: writeSave(generated.save), saveCreated: false })
    }

    frame = window.requestAnimationFrame(tick)
    return () => window.cancelAnimationFrame(frame)
  }, [
    boot.status,
    travel,
    boot.status === 'ready' ? boot.save.currentActivityId : null,
    boot.status === 'ready' ? boot.save.currentActionId : null,
    boot.status === 'ready' ? boot.save.actionStartedAt : null,
    boot.status === 'ready' ? boot.save.actionDurationMs : null,
  ])

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
  const currentAction = save.currentActionId
    ? database.launchIndexes.actionsById.get(save.currentActionId)
    : null
  const activityLabel = activity
    ? (activity['Contextual Name'] ?? activity['Internal Key'])
    : 'None'
  const actionSkill = currentAction
    ? database.launchIndexes.skillsById.get(currentAction['Relevant Skill ID'])
    : undefined

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
    if (!canTravelTo(database.launch, save.currentLocationId, destinationId, browseMapId)) {
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
    const result = validateActivityStart(database.launch, save, activityId)
    if (!result.ok) {
      setActivityError(result.reason)
      return
    }
    setActivityError(null)
    setLastMessage(null)
    setActionProgress(0)
    const started = beginActivitySave(save, activityId)
    const generated = generateNextAction(database.launch, started, activityId)
    updateSave(generated ? generated.save : started)
  }

  function stopActivity() {
    setActivityError(null)
    setActionProgress(0)
    setLastMessage(null)
    updateSave(clearActivitySave(save))
  }

  function requirementHint(row: ActivityRow): string | null {
    const result = validateActivityStart(database.launch, save, row['Activity ID'])
    return result.ok ? null : result.reason
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
            <>
              {activity && (
                <ActivityPanel
                  activity={activity}
                  action={currentAction ?? null}
                  save={save}
                  skill={actionSkill}
                  progress={actionProgress}
                  recentLoot={recentLoot}
                  lastMessage={lastMessage}
                  onStop={stopActivity}
                />
              )}
              <LocationView
                indexes={database.launchIndexes}
                location={location}
                currentActivityId={save.currentActivityId}
                activityError={activityError}
                requirementHint={requirementHint}
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
            </>
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

          {screen === 'inventory' && <InventoryPanel save={save} database={database} />}
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

function InventoryPanel({
  save,
  database,
}: {
  save: PlayerSave
  database: LoadedDatabase
}) {
  return (
    <section className="panel">
      <h1>Inventory</h1>
      {save.inventory.length === 0 ? (
        <p className="lead">No items yet. Gather resources to fill this list.</p>
      ) : (
        <ul className="plain-list">
          {save.inventory.map((stack) => (
            <li key={stack.itemId}>
              <strong>
                {database.launchIndexes.itemsById.get(stack.itemId)?.['Display Name'] ??
                  stack.itemId}
              </strong>
              <span className="muted"> × {stack.quantity}</span>
            </li>
          ))}
        </ul>
      )}
      <p className="muted tiny">Equip / unequip arrives in a later step.</p>
    </section>
  )
}
