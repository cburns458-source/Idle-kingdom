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
import { configNumber } from './game/activity/gathering'
import {
  applyCombatDefeat,
  applyCombatVictory,
  deathPauseRemainingMs,
  getEnemy,
  isDeathPaused,
  resolveCombatRound,
} from './game/combat/engine'
import { playerMaxHp } from './game/combat/stats'
import { addItemToInventory } from './game/activity/rewards'
import { equipItemFromInventory } from './game/equipment/loadout'
import { withRecalculatedVitals } from './game/equipment/vitals'
import {
  beginProductionQueue,
  cancelProductionActivity,
  completeProductionCraft,
  resolveProductionProgress,
} from './game/production/engine'
import { getRecipe, isStandardProductionActivity } from './game/production/recipes'
import { completeSpecialProject } from './game/projects/engine'
import type { SpecialProductionStation } from './game/projects/projects'
import { totalLevel, totalSkillXp } from './game/skills/totals'
import { ActivityPanel } from './ui/ActivityPanel'
import { BottomNav, type AppScreen } from './ui/BottomNav'
import { CombatPanel } from './ui/CombatPanel'
import { InventoryView } from './ui/InventoryView'
import { LocationView } from './ui/LocationView'
import { NamePrompt } from './ui/NamePrompt'
import { ProductionPicker, ProductionProgress } from './ui/ProductionPanel'
import { ProjectPicker } from './ui/ProjectPanel'
import { SkillsView } from './ui/SkillsView'
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
  const [roundProgress, setRoundProgress] = useState(0)
  const [pauseRemainingMs, setPauseRemainingMs] = useState(0)
  const [renamingCharacter, setRenamingCharacter] = useState(false)
  const [productionPickerActivityId, setProductionPickerActivityId] = useState<string | null>(null)
  const [specialStation, setSpecialStation] = useState<SpecialProductionStation | null>(null)
  const bootRef = useRef(boot)
  bootRef.current = boot

  useEffect(() => {
    let cancelled = false

    async function bootGame() {
      try {
        const database = await loadDatabase()
        const { save, created } = loadOrCreateSave(database.source)
        const resolved = resolveProductionProgress(database.launch, save)
        const nextSave = resolved.craftsCompleted > 0 ? writeSave(resolved.save) : resolved.save
        if (!cancelled) {
          const location = database.launchIndexes.locationsById.get(nextSave.currentLocationId)
          setBrowseMapId(location ? resolveActiveMapId(location) : MAIN_MAP_ID)
          setSelectedLocationId(nextSave.currentLocationId)
          if (resolved.messages[0]) setLastMessage(resolved.messages[0]!)
          setBoot({
            status: 'ready',
            database,
            save: nextSave,
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

  // Ensure an action exists while an activity is running (not during death pause).
  useEffect(() => {
    if (boot.status !== 'ready' || travel) return
    const { database, save } = boot
    if (!save.currentActivityId || save.currentActionId) return
    if (save.productionRecipeId) return
    if (isDeathPaused(save)) return

    const running = database.launchIndexes.activitiesById.get(save.currentActivityId)
    if (running && isStandardProductionActivity(database.launch, running)) return

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
      setActivityError('No actions remain for this activity.')
      return
    }
    setBoot({ ...boot, save: writeSave(generated.save), saveCreated: false })
  }, [boot, travel])

  const runningActivityId = boot.status === 'ready' ? boot.save.currentActivityId : null
  const runningActionId = boot.status === 'ready' ? boot.save.currentActionId : null
  const runningActionStartedAt = boot.status === 'ready' ? boot.save.actionStartedAt : null
  const runningActionDurationMs = boot.status === 'ready' ? boot.save.actionDurationMs : null

  // Progress + complete the current gathering action.
  useEffect(() => {
    if (boot.status !== 'ready' || travel) return
    const save = boot.save
    if (save.combatEnemyId || save.productionRecipeId) return
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
    boot,
    travel,
    runningActivityId,
    runningActionId,
    runningActionStartedAt,
    runningActionDurationMs,
  ])

  const productionRecipeId = boot.status === 'ready' ? boot.save.productionRecipeId : null
  const productionRemaining =
    boot.status === 'ready' ? boot.save.productionQuantityRemaining : null

  // Progress + complete standard production crafts.
  useEffect(() => {
    if (boot.status !== 'ready' || travel) return
    const save = boot.save
    if (!save.productionRecipeId || !save.actionStartedAt || !save.actionDurationMs) {
      return
    }

    let frame = 0
    let completed = false
    const startedAtMs = Date.parse(save.actionStartedAt)
    const durationMs = save.actionDurationMs

    const tick = () => {
      const elapsed = Date.now() - startedAtMs
      const progress = Math.min(1, elapsed / Math.max(1, durationMs))
      setActionProgress(progress)
      if (progress < 1) {
        frame = window.requestAnimationFrame(tick)
        return
      }
      if (completed) return
      completed = true

      const current = bootRef.current
      if (current.status !== 'ready' || !current.save.productionRecipeId) return
      const finished = completeProductionCraft(current.database.launch, current.save)
      if (!finished) return
      setLastMessage(
        `Crafted ${finished.outputQty} ${finished.outputName}` +
          (finished.xpGained > 0 ? ` · +${finished.xpGained} XP` : ''),
      )
      setActionProgress(0)
      setBoot({
        ...current,
        save: writeSave(finished.save),
        saveCreated: false,
      })
    }

    frame = window.requestAnimationFrame(tick)
    return () => window.cancelAnimationFrame(frame)
  }, [
    boot,
    travel,
    productionRecipeId,
    productionRemaining,
    runningActionStartedAt,
    runningActionDurationMs,
  ])

  const combatEnemyId = boot.status === 'ready' ? boot.save.combatEnemyId : null
  const combatRoundStartedAt = boot.status === 'ready' ? boot.save.combatRoundStartedAt : null
  const deathPauseUntil = boot.status === 'ready' ? boot.save.deathPauseUntil : null

  // Combat rounds + death pause.
  useEffect(() => {
    if (boot.status !== 'ready' || travel) return
    const { database, save } = boot
    if (!save.currentActivityId) {
      setRoundProgress(0)
      setPauseRemainingMs(0)
      return
    }

    const roundMs = configNumber(database.launch, 'combat_round_duration', 4) * 1000
    let frame = 0
    let resolved = false

    const tick = () => {
      const current = bootRef.current
      if (current.status !== 'ready') return
      const now = Date.now()
      const pauseLeft = deathPauseRemainingMs(current.save, now)
      setPauseRemainingMs(pauseLeft)

      if (pauseLeft > 0) {
        setRoundProgress(0)
        frame = window.requestAnimationFrame(tick)
        return
      }

      if (current.save.deathPauseUntil) {
        if (resolved) return
        resolved = true
        const resumed = {
          ...current.save,
          deathPauseUntil: null,
        }
        if (!activityStillValid(current.database.launch, resumed, resumed.currentActivityId!)) {
          setBoot({
            ...current,
            save: writeSave(clearActivitySave(resumed)),
            saveCreated: false,
          })
          setActivityError('Activity stopped after defeat — requirements no longer met.')
          return
        }
        const generated = generateNextAction(
          current.database.launch,
          resumed,
          resumed.currentActivityId!,
        )
        setBoot({
          ...current,
          save: writeSave(generated ? generated.save : resumed),
          saveCreated: false,
        })
        setLastMessage('Recovered. Resuming activity…')
        return
      }

      if (!current.save.combatEnemyId || !current.save.combatRoundStartedAt) {
        setRoundProgress(0)
        return
      }

      const started = Date.parse(current.save.combatRoundStartedAt)
      const progress = Math.min(1, (now - started) / roundMs)
      setRoundProgress(progress)
      if (progress < 1) {
        frame = window.requestAnimationFrame(tick)
        return
      }
      if (resolved) return
      resolved = true

      const enemy = getEnemy(current.database.launch, current.save.combatEnemyId)
      const action = current.save.currentActionId
        ? current.database.launchIndexes.actionsById.get(current.save.currentActionId)
        : undefined
      if (!enemy || !action || current.save.combatEnemyHp == null) {
        setBoot({
          ...current,
          save: writeSave(clearActivitySave(current.save)),
          saveCreated: false,
        })
        return
      }

      const round = resolveCombatRound(
        current.database.launch,
        current.save,
        enemy,
        current.save.combatEnemyHp,
      )

      if (round.outcome === 'victory') {
        const victoryResult = applyCombatVictory(
          current.database.launch,
          { ...current.save, combatEnemyHp: 0 },
          action,
          enemy,
        )
        const nextSave = victoryResult.save

        setRecentLoot((prev) => [...victoryResult.loot, ...prev].slice(0, 8))
        setLastMessage(
          [
            `Defeated ${enemy['Display Name']}`,
            victoryResult.xpGained > 0 ? `+${victoryResult.xpGained} Combat XP` : null,
            victoryResult.goldGained > 0 ? `+${victoryResult.goldGained} gold` : null,
            victoryResult.loot.map((loot) => `+${loot.quantity} ${loot.displayName}`).join(', ') ||
              null,
            victoryResult.foodConsumed
              ? `Ate ${victoryResult.foodName} (+${victoryResult.foodHealed} HP)`
              : null,
          ]
            .filter(Boolean)
            .join(' · '),
        )

        const activityId = current.save.currentActivityId!
        if (!activityStillValid(current.database.launch, nextSave, activityId)) {
          setBoot({
            ...current,
            save: writeSave(clearActivitySave(nextSave)),
            saveCreated: false,
          })
          return
        }
        const generated = generateNextAction(current.database.launch, nextSave, activityId)
        setRoundProgress(0)
        setBoot({
          ...current,
          save: writeSave(generated ? generated.save : nextSave),
          saveCreated: false,
        })
        return
      }

      if (round.outcome === 'defeat') {
        const defeated = applyCombatDefeat(current.database.launch, {
          ...current.save,
          currentHp: 0,
        })
        setLastMessage(`Defeated by ${enemy['Display Name']}. Recovering…`)
        setRoundProgress(0)
        setBoot({ ...current, save: writeSave(defeated), saveCreated: false })
        return
      }

      setLastMessage(
        `You hit ${round.playerHit}. ${enemy['Display Name']} hits ${round.enemyHit}.`,
      )
      setBoot({
        ...current,
        save: writeSave({
          ...current.save,
          currentHp: round.playerHp,
          combatEnemyHp: round.enemyHp,
          combatRoundStartedAt: new Date().toISOString(),
        }),
        saveCreated: false,
      })
    }

    frame = window.requestAnimationFrame(tick)
    return () => window.cancelAnimationFrame(frame)
  }, [boot, travel, combatEnemyId, combatRoundStartedAt, deathPauseUntil, runningActivityId])

  const ready = boot.status === 'ready' ? boot : null

  const overallXp = useMemo(
    () => (ready ? totalSkillXp(ready.save) : 0),
    [ready?.save.skills],
  )
  const overallLevel = useMemo(
    () => (ready ? totalLevel(ready.save) : 0),
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
  const combatEnemy =
    save.combatEnemyId != null ? getEnemy(database.launch, save.combatEnemyId) : undefined
  const maxHp = playerMaxHp(database.launch, save)
  const inCombat = Boolean(combatEnemy && save.combatEnemyHp != null)
  const productionRecipe = save.productionRecipeId
    ? getRecipe(database.launch, save.productionRecipeId)
    : undefined
  const inProduction = Boolean(productionRecipe && save.productionQuantityRemaining)
  const pickerActivity = productionPickerActivityId
    ? database.launchIndexes.activitiesById.get(productionPickerActivityId)
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

  const deathLocked = isDeathPaused(save) || pauseRemainingMs > 0

  function beginTravel(destinationId: string) {
    if (travel || deathLocked) return
    if (!canTravelTo(database.launch, save.currentLocationId, destinationId, browseMapId)) {
      return
    }
    const connection = findConnection(database.launch, save.currentLocationId, destinationId)
    setProductionPickerActivityId(null)
    setSpecialStation(null)
    // Interrupt primary activity immediately; refund remaining production materials.
    if (save.productionRecipeId) {
      updateSave(cancelProductionActivity(database.launch, save))
    } else if (save.currentActivityId) {
      updateSave(clearActivitySave(save))
    }
    setTravel({
      fromLocationId: save.currentLocationId,
      toLocationId: destinationId,
      startedAt: Date.now(),
      durationMs: travelDurationMs(connection),
    })
    setTravelProgress(0)
  }

  function startActivity(activityId: string) {
    if (deathLocked) {
      setActivityError('Cannot change activities while recovering from defeat.')
      return
    }
    const result = validateActivityStart(database.launch, save, activityId)
    if (!result.ok) {
      setActivityError(result.reason)
      return
    }
    setActivityError(null)
    setLastMessage(null)
    setActionProgress(0)

    const activityRow = database.launchIndexes.activitiesById.get(activityId)
    if (activityRow && isStandardProductionActivity(database.launch, activityRow)) {
      setSpecialStation(null)
      setProductionPickerActivityId(activityId)
      return
    }
    setSpecialStation(null)

    const started = beginActivitySave(save, activityId)
    const generated = generateNextAction(database.launch, started, activityId)
    updateSave(generated ? generated.save : started)
  }

  function confirmProduction(recipeId: string, quantity: number) {
    if (!productionPickerActivityId) return
    const started = beginActivitySave(save, productionPickerActivityId)
    const queued = beginProductionQueue(
      database.launch,
      started,
      productionPickerActivityId,
      recipeId,
      quantity,
    )
    if (!queued.ok) {
      setActivityError(queued.reason)
      return
    }
    setProductionPickerActivityId(null)
    setActivityError(null)
    setActionProgress(0)
    updateSave(queued.save)
  }

  function openSpecialProduction(station: SpecialProductionStation) {
    if (deathLocked) {
      setActivityError('Cannot use Special Production while recovering from defeat.')
      return
    }
    setProductionPickerActivityId(null)
    setActivityError(null)
    setSpecialStation(station)
  }

  function confirmSpecialProject(
    projectId: string,
    quantity: number,
    enchantSlotId: string | null,
  ) {
    if (!specialStation) return
    const result = completeSpecialProject(
      database.launch,
      save,
      projectId,
      quantity,
      enchantSlotId,
    )
    if (!result.ok) {
      setActivityError(result.reason)
      return
    }
    setSpecialStation(null)
    setActivityError(null)
    setLastMessage(
      [
        `Completed ${result.outputLabel}`,
        result.outputQty > 1 ? `×${result.outputQty}` : null,
        result.xpGained > 0 ? `+${result.xpGained.toLocaleString()} XP` : null,
        result.goldSpent > 0 ? `-${result.goldSpent} gold` : null,
      ]
        .filter(Boolean)
        .join(' · '),
    )
    updateSave(withRecalculatedVitals(database.launch, result.save))
  }

  function stopActivity() {
    if (deathLocked) return
    setActivityError(null)
    setActionProgress(0)
    setLastMessage(null)
    setProductionPickerActivityId(null)
    setSpecialStation(null)
    if (save.productionRecipeId) {
      updateSave(cancelProductionActivity(database.launch, save))
      return
    }
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
          characterName={save.characterName}
          totalLevel={overallLevel}
          totalXp={overallXp}
          gold={save.gold}
          currentHp={save.currentHp}
          maxHp={maxHp}
          activityLabel={activityLabel}
          locationLabel={location['Display Name']}
        />

        <div className="screen-body">
          {screen === 'location' && (
            <LocationView
              indexes={database.launchIndexes}
              db={database.launch}
              location={location}
              currentActivityId={save.currentActivityId}
              activityError={activityError}
              requirementHint={requirementHint}
              actionsLocked={deathLocked}
              onStartActivity={startActivity}
              onStopActivity={stopActivity}
              onOpenSpecialProduction={openSpecialProduction}
              onOpenMap={() => {
                setBrowseMapId(MAIN_MAP_ID)
                setSelectedLocationId(save.currentLocationId)
                setScreen('map')
              }}
              onOpenSubMap={() => {
                if (save.currentLocationId === CAVE_ENTRANCE_ID) setBrowseMapId(CAVE_MAP_ID)
                if (save.currentLocationId === CASTLE_GATEWAY_ID) setBrowseMapId(CASTLE_MAP_ID)
                setSelectedLocationId(save.currentLocationId)
                setScreen('map')
              }}
              statusPanel={
                <>
                  {specialStation && (
                    <ProjectPicker
                      db={database.launch}
                      save={save}
                      station={specialStation}
                      onCancel={() => setSpecialStation(null)}
                      onConfirm={confirmSpecialProject}
                    />
                  )}
                  {pickerActivity && !specialStation && (
                    <ProductionPicker
                      db={database.launch}
                      save={save}
                      activity={pickerActivity}
                      onCancel={() => setProductionPickerActivityId(null)}
                      onConfirm={confirmProduction}
                    />
                  )}
                  {activity && inCombat && combatEnemy && (
                    <CombatPanel
                      activity={activity}
                      enemy={combatEnemy}
                      enemyHp={save.combatEnemyHp ?? combatEnemy['Maximum HP']}
                      playerHp={save.currentHp}
                      playerMaxHp={maxHp}
                      roundProgress={roundProgress}
                      deathPauseRemainingMs={pauseRemainingMs}
                      lastCombatMessage={lastMessage}
                      onStop={stopActivity}
                    />
                  )}
                  {activity && inProduction && productionRecipe && pauseRemainingMs <= 0 && (
                    <ProductionProgress
                      activity={activity}
                      recipe={productionRecipe}
                      save={save}
                      progress={actionProgress}
                      lastMessage={lastMessage}
                      onStop={stopActivity}
                    />
                  )}
                  {activity &&
                    !inCombat &&
                    !inProduction &&
                    pauseRemainingMs <= 0 &&
                    !pickerActivity &&
                    !specialStation && (
                      <ActivityPanel
                        activity={activity}
                        action={currentAction ?? null}
                        save={save}
                        skill={actionSkill}
                        progress={actionProgress}
                        durationMs={save.actionDurationMs}
                        recentLoot={recentLoot}
                        lastMessage={lastMessage}
                        onStop={stopActivity}
                      />
                    )}
                  {activity && pauseRemainingMs > 0 && !inCombat && (
                    <section className="panel glass-panel">
                      <div className="activity-panel-head">
                        <div>
                          <h2>Recovering</h2>
                          <p className="muted">Death pause</p>
                        </div>
                      </div>
                      <p className="danger-note">
                        Resuming in {Math.ceil(pauseRemainingMs / 1000)}s…
                      </p>
                      <p className="muted tiny">
                        Travel and activities are locked until recovery finishes.
                      </p>
                      {lastMessage && <p className="loot-message">{lastMessage}</p>}
                    </section>
                  )}
                </>
              }
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
              travelDisabled={Boolean(travel) || deathLocked}
              travelLockReason={
                deathLocked ? 'Cannot travel while recovering from defeat.' : undefined
              }
            />
          )}

          {screen === 'skills' && <SkillsView db={database.launch} save={save} />}
          {screen === 'inventory' && (
            <InventoryView save={save} database={database} onChangeSave={updateSave} />
          )}
          {screen === 'settings' && (
            <SettingsPanel
              save={save}
              database={database}
              onChangeSave={updateSave}
              renaming={renamingCharacter}
              onStartRename={() => setRenamingCharacter(true)}
              onCancelRename={() => setRenamingCharacter(false)}
              onRename={(name) => {
                updateSave({ ...save, characterName: name })
                setRenamingCharacter(false)
              }}
            />
          )}
        </div>

        <BottomNav screen={screen} onChange={setScreen} />

        {travel && fromLocation && toLocation && (
          <TravelOverlay
            fromName={fromLocation['Display Name']}
            toName={toLocation['Display Name']}
            progress={travelProgress}
          />
        )}

        {!save.characterName && (
          <div className="name-prompt-overlay">
            <NamePrompt
              onSubmit={(name) => {
                updateSave({ ...save, characterName: name })
              }}
            />
          </div>
        )}
      </main>
    </div>
  )
}

function SettingsPanel({
  save,
  database,
  onChangeSave,
  renaming,
  onStartRename,
  onCancelRename,
  onRename,
}: {
  save: PlayerSave
  database: LoadedDatabase
  onChangeSave: (save: PlayerSave) => void
  renaming: boolean
  onStartRename: () => void
  onCancelRename: () => void
  onRename: (name: string) => void
}) {
  const bakedPotatoId = 'ITEM-0058'
  const steelPickaxeId = 'ITEM-0119'
  const potatoId = 'ITEM-0025'
  const copperOreId = 'ITEM-0003'
  const wildRootsId = 'ITEM-0030'

  function grantTestFood() {
    const withItems = addItemToInventory(save, bakedPotatoId, 5)
    const equipped = equipItemFromInventory(database.launch, withItems, bakedPotatoId)
    if (!equipped.ok) {
      onChangeSave(withRecalculatedVitals(database.launch, withItems))
      return
    }
    onChangeSave(withRecalculatedVitals(database.launch, equipped.save))
  }

  function grantSteelPickaxe() {
    onChangeSave(
      withRecalculatedVitals(database.launch, addItemToInventory(save, steelPickaxeId, 1)),
    )
  }

  function grantProductionMaterials() {
    let next = addItemToInventory(save, potatoId, 20)
    next = addItemToInventory(next, copperOreId, 20)
    next = addItemToInventory(next, wildRootsId, 20)
    onChangeSave(withRecalculatedVitals(database.launch, next))
  }

  function grantSmithingMaterials() {
    let next = addItemToInventory(save, 'ITEM-0074', 20)
    next = addItemToInventory(next, 'ITEM-0214', 10)
    next = addItemToInventory(next, 'ITEM-0084', 30)
    onChangeSave(withRecalculatedVitals(database.launch, next))
  }

  function grantArcanaMaterials() {
    let next = addItemToInventory(save, 'ITEM-0098', 5)
    next = addItemToInventory(next, 'ITEM-0011', 20)
    next = addItemToInventory(next, 'ITEM-0031', 30)
    next = addItemToInventory(next, 'ITEM-0040', 5)
    onChangeSave(withRecalculatedVitals(database.launch, next))
  }

  function raiseAlchemyToLevel10() {
    const alchemyId = 'SKL-0010'
    const xpAtLevel10 =
      database.launch.XPCurve.find((row) => row.Level === 10)?.['Total XP at Level'] ?? 10873
    const skills = save.skills.map((skill) => {
      if (skill.skillId !== alchemyId) return skill
      return {
        ...skill,
        level: Math.max(skill.level, 10),
        xp: Math.max(skill.xp, xpAtLevel10),
      }
    })
    if (!skills.some((skill) => skill.skillId === alchemyId)) {
      skills.push({ skillId: alchemyId, level: 10, xp: xpAtLevel10 })
    }
    onChangeSave({ ...save, skills })
  }

  if (renaming) {
    return (
      <NamePrompt
        title="Change character name"
        initialName={save.characterName ?? ''}
        submitLabel="Save name"
        onSubmit={onRename}
        onCancel={onCancelRename}
      />
    )
  }

  return (
    <section className="panel">
      <h1>Menu</h1>
      <p className="lead">Settings and temporary demo aids.</p>

      <div className="menu-name-block">
        <p className="muted tiny">Character</p>
        <p className="lead">{save.characterName ?? 'Unnamed'}</p>
        <button type="button" className="btn secondary" onClick={onStartRename}>
          Change name
        </button>
      </div>

      <div className="button-row">
        <button type="button" className="btn primary" onClick={grantTestFood}>
          Add & equip Baked Potato ×5
        </button>
        <button type="button" className="btn secondary" onClick={grantSteelPickaxe}>
          Give Steel Pickaxe
        </button>
        <button type="button" className="btn secondary" onClick={grantProductionMaterials}>
          Give production materials
        </button>
        <button type="button" className="btn secondary" onClick={raiseAlchemyToLevel10}>
          Set Alchemy to level 10
        </button>
        <button type="button" className="btn secondary" onClick={grantSmithingMaterials}>
          Give smithing materials
        </button>
        <button type="button" className="btn secondary" onClick={grantArcanaMaterials}>
          Give Arcana ingredients
        </button>
      </div>
      <p className="muted tiny">
        Demo aids: food, mining gear, production mats, Alchemy 10, smithing mats, and Enchanting
        Tablet / Essence / Fernleaf / Bull Horns for Arcana.
      </p>
    </section>
  )
}
