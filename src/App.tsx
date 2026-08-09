import { useEffect, useMemo, useRef, useState } from 'react'
import {
  activityStillValid,
  clearActivitySave,
  completeGatheringAction,
  generateNextAction,
  restoreActiveActionState,
  validateActivityStart,
} from './game/activity/engine'
import {
  cancelActivityTransition,
  hasRunningPrimaryActivity,
  isActivityTransitionPending,
  requestActivityStart,
  requestActivityStop,
  requestCancelForProductionPicker,
  requestProductionStart,
  resolveActivityTransitions,
  transitionRemainingMs,
} from './game/activity/transition'
import { loadDatabase, type LoadedDatabase } from './game/data/loadDatabase'
import type { ActionRewardBundle } from './game/activity/types'
import type { ActivityRow } from './game/data/types'
import { summarizeXpReward } from './game/activity/rewardSummary'
import { getSkillProgress } from './game/activity/xp'
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
  applyHostileTravelArrival,
  hostileForceMessage,
} from './game/world/hostility'
import {
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
import {
  applyAutoEquipProposal,
  proposeAutoEquipForActivity,
  type AutoEquipProposal,
} from './game/equipment/autoEquip'
import { equipItemFromInventory } from './game/equipment/loadout'
import { withRecalculatedVitals } from './game/equipment/vitals'
import { cancelProductionActivity, completeProductionCraft } from './game/production/engine'
import { getRecipe, isStandardProductionActivity } from './game/production/recipes'
import { asAchievementRows, syncProgressionMeta } from './game/achievements/progress'
import {
  asQuestRows,
  getQuestProgress,
  questStatusLabel,
} from './game/quests/quests'
import {
  resolveUnattendedProgress,
  stampUnattendedProgressAt,
} from './game/unattended/resolve'
import { completeSpecialProject } from './game/projects/engine'
import type { SpecialProductionStation } from './game/projects/projects'
import { totalLevel, totalSkillXp } from './game/skills/totals'
import { ActivityPanel } from './ui/ActivityPanel'
import {
  AfkSummaryPanel,
  afkSummaryFromUnattended,
  exampleAfkSummary,
  type AfkSummaryData,
} from './ui/AfkSummaryPanel'
import { BottomNav, type AppScreen } from './ui/BottomNav'
import { CombatPanel } from './ui/CombatPanel'
import { InventoryView } from './ui/InventoryView'
import { LocationView } from './ui/LocationView'
import { NamePrompt } from './ui/NamePrompt'
import { NpcPanel } from './ui/NpcPanel'
import { ProductionPicker, ProductionProgress } from './ui/ProductionPanel'
import { ActivityTransitionPanel } from './ui/ActivityTransitionPanel'
import { AutoEquipPrompt } from './ui/AutoEquipPrompt'
import { ProjectCompletePopup } from './ui/ProjectCompletePopup'
import { ProjectPicker } from './ui/ProjectPanel'
import { getProject } from './game/projects/projects'
import { ShopPanel } from './ui/ShopPanel'
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
  const [recentRewards, setRecentRewards] = useState<ActionRewardBundle[]>([])
  const [lastMessage, setLastMessage] = useState<string | null>(null)
  const [roundProgress, setRoundProgress] = useState(0)
  const [pauseRemainingMs, setPauseRemainingMs] = useState(0)
  const [renamingCharacter, setRenamingCharacter] = useState(false)
  const [productionPickerActivityId, setProductionPickerActivityId] = useState<string | null>(null)
  const [specialStation, setSpecialStation] = useState<SpecialProductionStation | null>(null)
  const [activeShopId, setActiveShopId] = useState<string | null>(null)
  const [activeNpcId, setActiveNpcId] = useState<string | null>(null)
  const [afkSummary, setAfkSummary] = useState<AfkSummaryData | null>(null)
  const [projectCompletePopup, setProjectCompletePopup] = useState<{
    projectName: string
    lines: string[]
  } | null>(null)
  const [autoEquipPrompt, setAutoEquipPrompt] = useState<AutoEquipProposal | null>(null)
  const [transitionRemaining, setTransitionRemaining] = useState(0)
  const [deferredProductionPickerId, setDeferredProductionPickerId] = useState<string | null>(
    null,
  )
  const bootRef = useRef(boot)
  bootRef.current = boot

  useEffect(() => {
    let cancelled = false

    async function bootGame() {
      try {
        const database = await loadDatabase()
        const { save, created } = loadOrCreateSave(database.source)
        const resolved = resolveUnattendedProgress(database.launch, save)
        const synced = syncProgressionMeta(database.launch, resolved.save)
        const nextSave = writeSave(synced)
        if (!cancelled) {
          const location = database.launchIndexes.locationsById.get(nextSave.currentLocationId)
          setBrowseMapId(location ? resolveActiveMapId(location) : MAIN_MAP_ID)
          setSelectedLocationId(nextSave.currentLocationId)
          if (resolved.messages[0]) setLastMessage(resolved.messages[0]!)
          const hadAfkProgress =
            resolved.gatheringActions > 0 ||
            resolved.craftsCompleted > 0 ||
            resolved.combatVictories > 0 ||
            resolved.combatDeaths > 0
          if (hadAfkProgress) {
            setAfkSummary(afkSummaryFromUnattended(resolved))
          }
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
      const progress =
        travel.durationMs <= 0 ? 1 : Math.min(1, elapsed / travel.durationMs)
      setTravelProgress(progress)
      if (progress >= 1) {
        const current = bootRef.current
        if (current.status !== 'ready') return
        const arrived = applyHostileTravelArrival(
          current.database.launch,
          current.save,
          travel.toLocationId,
        )
        const saved = persistSave(arrived.save)
        const location = current.database.launchIndexes.locationsById.get(saved.currentLocationId)
        setBoot({ ...current, save: saved, saveCreated: false })
        setBrowseMapId(location ? resolveActiveMapId(location) : MAIN_MAP_ID)
        setSelectedLocationId(saved.currentLocationId)
        setScreen('location')
        setActionProgress(0)
        const forceMessage = hostileForceMessage(current.database.launch, arrived)
        if (arrived.forcedActivityId) {
          setActivityError(null)
          setLastMessage(forceMessage)
        } else if (arrived.forceBlockedReason) {
          setLastMessage(null)
          setActivityError(forceMessage)
        } else {
          setLastMessage(null)
          setActivityError(null)
        }
        setTravel(null)
        setTravelProgress(0)
        return
      }
      frame = window.requestAnimationFrame(tick)
    }

    frame = window.requestAnimationFrame(tick)
    return () => window.cancelAnimationFrame(frame)
  }, [travel, boot.status])

  // Resolve Primary Activity start/stop delays.
  useEffect(() => {
    if (boot.status !== 'ready' || travel) return
    if (!boot.save.activityTransition) {
      setTransitionRemaining(0)
      return
    }

    let frame = 0
    const tick = () => {
      const current = bootRef.current
      if (current.status !== 'ready') return
      const now = Date.now()
      const remaining = transitionRemainingMs(current.save, now)
      setTransitionRemaining(remaining)

      if (remaining <= 0 && current.save.activityTransition) {
        const resolved = resolveActivityTransitions(current.database.launch, current.save, now)
        if (resolved !== current.save) {
          const saved = persistSave(resolved)
          setBoot({ ...current, save: saved, saveCreated: false })
          setActionProgress(0)
        }
        return
      }

      frame = window.requestAnimationFrame(tick)
    }

    frame = window.requestAnimationFrame(tick)
    return () => window.cancelAnimationFrame(frame)
  }, [boot.status, boot.status === 'ready' ? boot.save.activityTransition : null, travel])

  // After a cancel delay finishes, open a deferred Standard Production picker.
  useEffect(() => {
    if (boot.status !== 'ready' || travel) return
    if (!deferredProductionPickerId) return
    if (boot.save.activityTransition) return
    if (hasRunningPrimaryActivity(boot.save)) return
    setProductionPickerActivityId(deferredProductionPickerId)
    setDeferredProductionPickerId(null)
  }, [
    boot.status,
    boot.status === 'ready' ? boot.save.activityTransition : null,
    boot.status === 'ready' ? boot.save.currentActivityId : null,
    boot.status === 'ready' ? boot.save.productionRecipeId : null,
    deferredProductionPickerId,
    travel,
  ])

  // Ensure an action exists while an activity is running (not during death pause).
  useEffect(() => {
    if (boot.status !== 'ready' || travel) return
    const { database, save } = boot
    if (!save.currentActivityId || save.currentActionId) return
    if (save.productionRecipeId) return
    if (isDeathPaused(save)) return
    if (save.activityTransition?.kind === 'starting') return

    const running = database.launchIndexes.activitiesById.get(save.currentActivityId)
    if (running && isStandardProductionActivity(database.launch, running)) return

    if (!activityStillValid(database.launch, save, save.currentActivityId)) {
      const stopped = persistSave(clearActivitySave(save))
      setBoot({ ...boot, save: stopped, saveCreated: false })
      setActivityError('Activity stopped — requirements are no longer met.')
      return
    }

    const generated = generateNextAction(database.launch, save, save.currentActivityId)
    if (!generated) {
      const stopped = persistSave(clearActivitySave(save))
      setBoot({ ...boot, save: stopped, saveCreated: false })
      setActivityError('No actions remain for this activity.')
      return
    }
    setBoot({ ...boot, save: persistSave(generated.save), saveCreated: false })
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
        const stopped = persistSave(clearActivitySave(current.save))
        setBoot({ ...current, save: stopped, saveCreated: false })
        return
      }

      const finished = completeGatheringAction(current.database.launch, current.save, action)
      let nextSave = finished.save
      const gatheringBundle: ActionRewardBundle = {
        id: `${finished.result.actionId}-${Date.now()}`,
        xpRewards: finished.result.xpRewards,
        loot: finished.result.loot,
        goldGained: finished.result.goldGained,
      }
      setRecentRewards((prev) => [gatheringBundle, ...prev].slice(0, 4))
      setLastMessage(null)

      const activityId = current.save.currentActivityId
      if (!activityStillValid(current.database.launch, nextSave, activityId)) {
        nextSave = clearActivitySave(nextSave)
        setActivityError('Activity stopped — requirements are no longer met.')
        setActionProgress(0)
        setBoot({ ...current, save: persistSave(nextSave), saveCreated: false })
        return
      }

      const generated = generateNextAction(current.database.launch, nextSave, activityId)
      if (!generated) {
        setBoot({
          ...current,
          save: persistSave(clearActivitySave(nextSave)),
          saveCreated: false,
        })
        setActionProgress(0)
        return
      }

      setActionProgress(0)
      setBoot({ ...current, save: persistSave(generated.save), saveCreated: false })
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
        save: persistSave(finished.save),
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
            save: persistSave(clearActivitySave(resumed)),
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
          save: persistSave(generated ? generated.save : resumed),
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
          save: persistSave(clearActivitySave(current.save)),
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

        const combatLevelBefore = getSkillProgress(current.save, 'SKL-0001').level
        const combatLevelAfter = getSkillProgress(victoryResult.save, 'SKL-0001').level
        const combatXpReward = summarizeXpReward(
          current.database.launch,
          victoryResult.save,
          'SKL-0001',
          victoryResult.xpGained,
          combatLevelAfter > combatLevelBefore ? combatLevelAfter : null,
        )
        const combatBundle: ActionRewardBundle = {
          id: `combat-${enemy['Enemy ID']}-${Date.now()}`,
          xpRewards: combatXpReward ? [combatXpReward] : [],
          loot: victoryResult.loot,
          goldGained: victoryResult.goldGained,
        }
        setRecentRewards((prev) => [combatBundle, ...prev].slice(0, 4))
        setLastMessage(
          victoryResult.foodConsumed
            ? `Ate ${victoryResult.foodName} (+${victoryResult.foodHealed} HP)`
            : `Defeated ${enemy['Display Name']}`,
        )

        const activityId = current.save.currentActivityId!
        if (!activityStillValid(current.database.launch, nextSave, activityId)) {
          setBoot({
            ...current,
            save: persistSave(clearActivitySave(nextSave)),
            saveCreated: false,
          })
          return
        }
        const generated = generateNextAction(current.database.launch, nextSave, activityId)
        setRoundProgress(0)
        setBoot({
          ...current,
          save: persistSave(generated ? generated.save : nextSave),
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
        setBoot({ ...current, save: persistSave(defeated), saveCreated: false })
        return
      }

      setLastMessage(
        `You hit ${round.playerHit}. ${enemy['Display Name']} hits ${round.enemyHit}.`,
      )
      setBoot({
        ...current,
        save: persistSave({
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

  function persistSave(next: PlayerSave): PlayerSave {
    const current = bootRef.current
    const stamped = stampUnattendedProgressAt(next)
    const synced =
      current.status === 'ready'
        ? syncProgressionMeta(current.database.launch, stamped)
        : stamped
    return writeSave(synced)
  }

  function updateSave(next: PlayerSave) {
    const saved = persistSave(next)
    setBoot((bootState) =>
      bootState.status === 'ready'
        ? { ...bootState, save: saved, saveCreated: false }
        : bootState,
    )
  }

  const deathLocked = isDeathPaused(save) || pauseRemainingMs > 0
  const transitionLocked = isActivityTransitionPending(save) || transitionRemaining > 0
  const activityActionsLocked = deathLocked || transitionLocked
  const pendingTransition = save.activityTransition
  const pendingTransitionActivity = pendingTransition
    ? database.launchIndexes.activitiesById.get(pendingTransition.activityId)
    : undefined

  function beginTravel(destinationId: string) {
    if (travel || deathLocked) return
    if (!canTravelTo(database.launch, save.currentLocationId, destinationId, browseMapId)) {
      return
    }
    const connection = findConnection(database.launch, save.currentLocationId, destinationId)
    setProductionPickerActivityId(null)
    setSpecialStation(null)
    setActiveShopId(null)
    setActiveNpcId(null)
    // Interrupt primary activity immediately; refund remaining production materials.
    let working = save
    if (working.productionRecipeId) {
      working = cancelProductionActivity(database.launch, working)
    } else if (working.currentActivityId) {
      working = clearActivitySave(working)
    }

    const durationMs = travelDurationMs(connection)
    if (durationMs <= 0) {
      const arrived = applyHostileTravelArrival(database.launch, working, destinationId)
      updateSave(arrived.save)
      const nextLocation = database.launchIndexes.locationsById.get(destinationId)
      setBrowseMapId(nextLocation ? resolveActiveMapId(nextLocation) : MAIN_MAP_ID)
      setSelectedLocationId(destinationId)
      setScreen('location')
      setActionProgress(0)
      const forceMessage = hostileForceMessage(database.launch, arrived)
      if (arrived.forcedActivityId) {
        setActivityError(null)
        setLastMessage(forceMessage)
      } else if (arrived.forceBlockedReason) {
        setLastMessage(null)
        setActivityError(forceMessage)
      } else {
        setLastMessage(null)
        setActivityError(null)
      }
      setTravel(null)
      setTravelProgress(0)
      return
    }

    if (working !== save) updateSave(working)
    setTravel({
      fromLocationId: save.currentLocationId,
      toLocationId: destinationId,
      startedAt: Date.now(),
      durationMs,
    })
    setTravelProgress(0)
  }

  function startActivity(
    activityId: string,
    fromSave: PlayerSave = save,
    allowAutoEquipPrompt = true,
  ) {
    if (deathLocked) {
      setActivityError('Cannot change activities while recovering from defeat.')
      return
    }
    if (isActivityTransitionPending(fromSave)) {
      setActivityError('Wait for the current start/stop delay to finish.')
      return
    }
    const result = validateActivityStart(database.launch, fromSave, activityId)
    if (!result.ok) {
      if (allowAutoEquipPrompt) {
        const proposal = proposeAutoEquipForActivity(
          database.launch,
          fromSave,
          activityId,
          result.reason,
        )
        if (proposal) {
          setAutoEquipPrompt(proposal)
          setActivityError(null)
          return
        }
      }
      setActivityError(result.reason)
      return
    }
    setAutoEquipPrompt(null)
    setActivityError(null)
    setLastMessage(null)
    setActionProgress(0)

    const activityRow = database.launchIndexes.activitiesById.get(activityId)
    if (activityRow && isStandardProductionActivity(database.launch, activityRow)) {
      setSpecialStation(null)
      // Cancel any running Primary Activity before opening the production picker.
      if (
        hasRunningPrimaryActivity(fromSave) &&
        (fromSave.currentActivityId !== activityId || fromSave.productionRecipeId)
      ) {
        const cancel = requestCancelForProductionPicker(database.launch, fromSave, activityId)
        if (!cancel.ok) {
          setActivityError(cancel.reason)
          return
        }
        if (cancel.save.activityTransition) {
          setDeferredProductionPickerId(activityId)
          setProductionPickerActivityId(null)
          updateSave(cancel.save)
          return
        }
      }
      setDeferredProductionPickerId(null)
      setProductionPickerActivityId(activityId)
      if (fromSave !== save) updateSave(fromSave)
      return
    }
    setSpecialStation(null)
    setProductionPickerActivityId(null)
    setDeferredProductionPickerId(null)

    const requested = requestActivityStart(database.launch, fromSave, activityId)
    if (!requested.ok) {
      setActivityError(requested.reason)
      return
    }
    updateSave(requested.save)
  }

  function confirmAutoEquipAndStart() {
    if (!autoEquipPrompt) return
    const equipped = applyAutoEquipProposal(database.launch, save, autoEquipPrompt)
    if (!equipped.ok) {
      setAutoEquipPrompt(null)
      setActivityError(equipped.reason)
      return
    }
    const activityId = autoEquipPrompt.activityId
    setAutoEquipPrompt(null)
    startActivity(activityId, withRecalculatedVitals(database.launch, equipped.save), false)
  }

  function confirmProduction(recipeId: string, quantity: number) {
    if (!productionPickerActivityId) return
    const requested = requestProductionStart(
      database.launch,
      save,
      productionPickerActivityId,
      recipeId,
      quantity,
    )
    if (!requested.ok) {
      setActivityError(requested.reason)
      return
    }
    setProductionPickerActivityId(null)
    setActivityError(null)
    setActionProgress(0)
    updateSave(requested.save)
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
    enchantTargetId: string | null,
  ) {
    if (!specialStation) return
    const result = completeSpecialProject(
      database.launch,
      save,
      projectId,
      quantity,
      enchantTargetId,
    )
    if (!result.ok) {
      setActivityError(result.reason)
      return
    }
    const projectName =
      getProject(database.launch, projectId)?.['Display Name'] ?? result.outputLabel
    const lines = [
      result.outputQty > 1
        ? `${result.outputLabel} ×${result.outputQty}`
        : result.outputLabel,
      result.xpGained > 0 ? `+${result.xpGained.toLocaleString()} XP` : null,
      result.goldSpent > 0 ? `Spent ${result.goldSpent.toLocaleString()} gold` : null,
      quantity > 1 ? `Crafted ${quantity} times` : null,
    ].filter(Boolean) as string[]

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
    setProjectCompletePopup({ projectName, lines })
    updateSave(withRecalculatedVitals(database.launch, result.save))
  }

  function stopActivity() {
    if (deathLocked) return
    if (isActivityTransitionPending(save)) {
      setActivityError('Wait for the current start/stop delay to finish.')
      return
    }
    setActivityError(null)
    setActionProgress(0)
    setLastMessage(null)
    setProductionPickerActivityId(null)
    setSpecialStation(null)
    const requested = requestActivityStop(database.launch, save)
    if (!requested.ok) {
      setActivityError(requested.reason)
      return
    }
    updateSave(requested.save)
  }

  function cancelPendingActivityChange() {
    if (!save.activityTransition) return
    setActivityError(null)
    setTransitionRemaining(0)
    setDeferredProductionPickerId(null)
    updateSave(cancelActivityTransition(save))
  }

  function requirementHint(row: ActivityRow): string | null {
    const result = validateActivityStart(database.launch, save, row['Activity ID'])
    return result.ok ? null : result.reason
  }

  return (
    <div className="app-shell">
      <main
        className={screen === 'map' ? 'portrait-frame portrait-frame-map' : 'portrait-frame'}
        aria-label="Idle Kingdoms"
      >
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

        <div className={screen === 'map' ? 'screen-body screen-body-map' : 'screen-body'}>
          {screen === 'location' && (
            <LocationView
              indexes={database.launchIndexes}
              db={database.launch}
              location={location}
              currentActivityId={save.currentActivityId}
              activityError={activityError}
              requirementHint={requirementHint}
              actionsLocked={activityActionsLocked}
              onStartActivity={startActivity}
              onStopActivity={stopActivity}
              onOpenSpecialProduction={(station) => {
                setActiveShopId(null)
                setActiveNpcId(null)
                openSpecialProduction(station)
              }}
              onOpenShop={(shopId) => {
                setSpecialStation(null)
                setProductionPickerActivityId(null)
                setActiveNpcId(null)
                setActiveShopId(shopId)
              }}
              onOpenNpc={(npcId) => {
                setSpecialStation(null)
                setProductionPickerActivityId(null)
                setActiveShopId(null)
                setActiveNpcId(npcId)
              }}
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
                  {activeShopId && (
                    <ShopPanel
                      db={database.launch}
                      save={save}
                      shopId={activeShopId}
                      onClose={() => setActiveShopId(null)}
                      onComplete={(next, message) => {
                        updateSave(next)
                        setLastMessage(message)
                      }}
                    />
                  )}
                  {activeNpcId &&
                    (() => {
                      const npc = database.launch.NPCs.find(
                        (row) => row['NPC ID'] === activeNpcId,
                      )
                      if (!npc) return null
                      return (
                        <NpcPanel
                          db={database.launch}
                          save={save}
                          npc={npc}
                          onClose={() => setActiveNpcId(null)}
                          onChangeSave={(next, message) => {
                            updateSave(next)
                            if (message) setLastMessage(message)
                          }}
                          onOpenShop={(shopId) => {
                            setActiveNpcId(null)
                            setActiveShopId(shopId)
                          }}
                        />
                      )
                    })()}
                  {specialStation && !activeShopId && !activeNpcId && (
                    <ProjectPicker
                      db={database.launch}
                      save={save}
                      station={specialStation}
                      onCancel={() => setSpecialStation(null)}
                      onConfirm={confirmSpecialProject}
                    />
                  )}
                  {pickerActivity && !specialStation && !activeShopId && !activeNpcId && (
                    <ProductionPicker
                      db={database.launch}
                      save={save}
                      activity={pickerActivity}
                      onCancel={() => setProductionPickerActivityId(null)}
                      onConfirm={confirmProduction}
                    />
                  )}
                  {pendingTransition && !activeShopId && !activeNpcId && (
                    <ActivityTransitionPanel
                      transition={pendingTransition}
                      activity={pendingTransitionActivity}
                      remainingMs={transitionRemaining}
                      onCancel={cancelPendingActivityChange}
                    />
                  )}
                  {activity && inCombat && combatEnemy && !activeShopId && !activeNpcId && (
                    <CombatPanel
                      activity={activity}
                      enemy={combatEnemy}
                      enemyHp={save.combatEnemyHp ?? combatEnemy['Maximum HP']}
                      playerHp={save.currentHp}
                      playerMaxHp={maxHp}
                      roundProgress={roundProgress}
                      deathPauseRemainingMs={pauseRemainingMs}
                      lastCombatMessage={lastMessage}
                      recentRewards={recentRewards}
                      itemsById={database.launchIndexes.itemsById}
                      onStop={stopActivity}
                    />
                  )}
                  {activity &&
                    inProduction &&
                    productionRecipe &&
                    pauseRemainingMs <= 0 &&
                    !activeShopId &&
                    !activeNpcId && (
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
                    !specialStation &&
                    !activeShopId &&
                    !activeNpcId && (
                      <ActivityPanel
                        activity={activity}
                        action={currentAction ?? null}
                        save={save}
                        skill={actionSkill}
                        progress={actionProgress}
                        durationMs={save.actionDurationMs}
                        recentRewards={recentRewards}
                        itemsById={database.launchIndexes.itemsById}
                        onStop={stopActivity}
                      />
                    )}
                  {activity && pauseRemainingMs > 0 && !inCombat && !activeShopId && !activeNpcId && (
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
              onBrowseMap={setBrowseMapId}
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
              onPreviewAfkSummary={() => setAfkSummary(exampleAfkSummary())}
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

        {afkSummary ? (
          <AfkSummaryPanel summary={afkSummary} onClose={() => setAfkSummary(null)} />
        ) : null}

        {projectCompletePopup ? (
          <ProjectCompletePopup
            projectName={projectCompletePopup.projectName}
            lines={projectCompletePopup.lines}
            onClose={() => setProjectCompletePopup(null)}
          />
        ) : null}

        {autoEquipPrompt ? (
          <AutoEquipPrompt
            proposal={autoEquipPrompt}
            onCancel={() => {
              setActivityError(autoEquipPrompt.failureReason)
              setAutoEquipPrompt(null)
            }}
            onConfirm={confirmAutoEquipAndStart}
          />
        ) : null}
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
  onPreviewAfkSummary,
}: {
  save: PlayerSave
  database: LoadedDatabase
  onChangeSave: (save: PlayerSave) => void
  renaming: boolean
  onStartRename: () => void
  onCancelRename: () => void
  onRename: (name: string) => void
  onPreviewAfkSummary: () => void
}) {
  const bakedPotatoId = 'ITEM-0058'
  const steelPickaxeId = 'ITEM-0119'
  const potatoId = 'ITEM-0025'
  const copperOreId = 'ITEM-0003'
  const wildRootsId = 'ITEM-0030'

  const launchSkills = database.launch.Skills
  const launchItems = database.launch.Items
  const levelCap = configNumber(database.launch, 'display_level_cap', 100)

  const [menuTab, setMenuTab] = useState<'settings' | 'achievements'>('settings')
  const [selectedSkillId, setSelectedSkillId] = useState(
    launchSkills[0]?.['Skill ID'] ?? 'SKL-0001',
  )
  const [itemSearch, setItemSearch] = useState('')
  const achievements = asAchievementRows(database.launch)
  const quests = asQuestRows(database.launch)
  const filteredItems = useMemo(() => {
    const needle = itemSearch.trim().toLowerCase()
    const list = !needle
      ? launchItems
      : launchItems.filter(
          (item) =>
            item['Display Name'].toLowerCase().includes(needle) ||
            item['Internal Key'].toLowerCase().includes(needle) ||
            item['Item ID'].toLowerCase().includes(needle) ||
            (item.Category ?? '').toLowerCase().includes(needle),
        )
    return [...list].sort((a, b) =>
      a['Display Name'].localeCompare(b['Display Name'], undefined, { sensitivity: 'base' }),
    )
  }, [itemSearch, launchItems])
  const [selectedItemId, setSelectedItemId] = useState(filteredItems[0]?.['Item ID'] ?? '')

  useEffect(() => {
    if (filteredItems.length === 0) return
    if (!filteredItems.some((item) => item['Item ID'] === selectedItemId)) {
      setSelectedItemId(filteredItems[0]!['Item ID'])
    }
  }, [filteredItems, selectedItemId])

  function xpAtLevel(level: number): number {
    const row = database.launch.XPCurve.find((entry) => entry.Level === level)
    return row?.['Total XP at Level'] ?? 0
  }

  function raiseSelectedSkillBy10() {
    if (!selectedSkillId) return
    const current =
      save.skills.find((skill) => skill.skillId === selectedSkillId)?.level ?? 1
    const nextLevel = Math.min(levelCap, current + 10)
    const nextXp = Math.max(
      save.skills.find((skill) => skill.skillId === selectedSkillId)?.xp ?? 0,
      xpAtLevel(nextLevel),
    )
    const skills = save.skills.map((skill) =>
      skill.skillId === selectedSkillId
        ? { ...skill, level: nextLevel, xp: nextXp }
        : skill,
    )
    if (!skills.some((skill) => skill.skillId === selectedSkillId)) {
      skills.push({ skillId: selectedSkillId, level: nextLevel, xp: nextXp })
    }
    onChangeSave({ ...save, skills })
  }

  function grantSelectedItem100() {
    if (!selectedItemId) return
    onChangeSave(
      withRecalculatedVitals(
        database.launch,
        addItemToInventory(save, selectedItemId, 100),
      ),
    )
  }

  function resetAllSkills() {
    const skills = save.skills.map((skill) => ({
      ...skill,
      level: 1,
      xp: 0,
    }))
    onChangeSave({ ...save, skills })
  }

  function clearAllItems() {
    const slots = { ...save.equipment.slots }
    for (const slotId of Object.keys(slots)) {
      slots[slotId] = null
    }
    onChangeSave(
      withRecalculatedVitals(database.launch, {
        ...save,
        inventory: [],
        equipment: { slots },
      }),
    )
  }

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
    let next = addItemToInventory(save, 'ITEM-0098', 5) // Enchanting Tablet
    next = addItemToInventory(next, 'ITEM-0099', 5) // Spell Tablet
    next = addItemToInventory(next, 'ITEM-0011', 20) // Essence
    next = addItemToInventory(next, 'ITEM-0031', 30) // Fernleaf
    next = addItemToInventory(next, 'ITEM-0040', 20) // Bull Horns
    next = addItemToInventory(next, 'ITEM-0295', 1) // Strength Spell item
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
    <section className="panel menu-panel">
      <h1>Menu</h1>
      <div className="menu-tabs" role="tablist" aria-label="Menu sections">
        <button
          type="button"
          role="tab"
          aria-selected={menuTab === 'settings'}
          className={menuTab === 'settings' ? 'menu-tab active' : 'menu-tab'}
          onClick={() => setMenuTab('settings')}
        >
          Settings
        </button>
        <button
          type="button"
          role="tab"
          aria-selected={menuTab === 'achievements'}
          className={menuTab === 'achievements' ? 'menu-tab active' : 'menu-tab'}
          onClick={() => setMenuTab('achievements')}
        >
          Achievements
        </button>
      </div>

      {menuTab === 'achievements' ? (
        <div role="tabpanel" className="menu-tab-panel">
          <p className="lead">Skill milestones unlocked on this save.</p>
          <ul className="achievement-list">
            {achievements.map((achievement) => {
              const unlocked = save.achievements.some(
                (row) => row.achievementId === achievement['Achievement ID'] && row.unlocked,
              )
              const skillName =
                database.launch.Skills.find(
                  (skill) => skill['Skill ID'] === achievement['Target Skill ID'],
                )?.['Display Name'] ?? 'Skill'
              return (
                <li
                  key={achievement['Achievement ID']}
                  className={unlocked ? 'unlocked' : undefined}
                >
                  <strong>{achievement['Display Name']}</strong>
                  <span className="muted tiny">
                    {unlocked
                      ? 'Unlocked'
                      : `Reach ${skillName} level ${achievement['Required Level'] ?? 50}`}
                  </span>
                </li>
              )
            })}
          </ul>

          <h2 className="menu-section-heading">Quests</h2>
          <p className="muted tiny">Quest log for this save.</p>
          <ul className="achievement-list quest-log-list">
            {quests.map((quest) => {
              const progress = getQuestProgress(save, quest['Quest ID'])
              const npcName =
                database.launch.NPCs.find((npc) => npc['NPC ID'] === quest['NPC ID'])?.[
                  'Display Name'
                ] ?? 'NPC'
              return (
                <li
                  key={quest['Quest ID']}
                  className={progress.status === 'completed' ? 'unlocked' : undefined}
                >
                  <div className="quest-log-copy">
                    <strong>{quest['Display Name']}</strong>
                    <span className="muted tiny">
                      {quest.Summary ?? 'No summary.'} · {npcName}
                    </span>
                  </div>
                  <span className="muted tiny">{questStatusLabel(progress.status)}</span>
                </li>
              )
            })}
          </ul>
        </div>
      ) : (
        <div role="tabpanel" className="menu-tab-panel">
          <p className="lead">Settings and temporary demo aids.</p>

          <div className="menu-name-block">
            <p className="muted tiny">Character</p>
            <p className="lead">{save.characterName ?? 'Unnamed'}</p>
            <button type="button" className="btn secondary" onClick={onStartRename}>
              Change name
            </button>
          </div>

          <div className="menu-demo-block">
            <p className="muted tiny">AFK summary</p>
            <p className="muted tiny">
              Preview the offline catch-up report shown when you return after time away.
            </p>
            <button type="button" className="btn secondary" onClick={onPreviewAfkSummary}>
              Example AFK summary
            </button>
          </div>

          <div className="menu-demo-block">
            <p className="muted tiny">Raise skill +10</p>
            <label className="field-label" htmlFor="menu-skill-select">
              Skill
            </label>
            <select
              id="menu-skill-select"
              className="text-input"
              value={selectedSkillId}
              onChange={(event) => setSelectedSkillId(event.target.value)}
            >
              {launchSkills.map((skill) => {
                const level =
                  save.skills.find((entry) => entry.skillId === skill['Skill ID'])?.level ?? 1
                return (
                  <option key={skill['Skill ID']} value={skill['Skill ID']}>
                    {skill['Display Name']} (Lv {level})
                  </option>
                )
              })}
            </select>
            <div className="button-row">
              <button type="button" className="btn primary" onClick={raiseSelectedSkillBy10}>
                Raise skill by 10 levels
              </button>
              <button type="button" className="btn secondary" onClick={resetAllSkills}>
                Reset skills
              </button>
            </div>
          </div>

          <div className="menu-demo-block">
            <p className="muted tiny">Add items ×100</p>
            <label className="field-label" htmlFor="menu-item-search">
              Search items
            </label>
            <input
              id="menu-item-search"
              className="text-input"
              type="search"
              enterKeyHint="search"
              placeholder="Type an item name…"
              value={itemSearch}
              onChange={(event) => setItemSearch(event.target.value)}
              autoComplete="off"
            />
            <label className="field-label" htmlFor="menu-item-select">
              Item
              {itemSearch.trim()
                ? ` (${filteredItems.length} shown)`
                : ` (${launchItems.length})`}
            </label>
            {filteredItems.length === 0 ? (
              <p className="muted tiny">No items match that search.</p>
            ) : (
              <select
                id="menu-item-select"
                className="text-input"
                value={
                  filteredItems.some((item) => item['Item ID'] === selectedItemId)
                    ? selectedItemId
                    : filteredItems[0]!['Item ID']
                }
                onChange={(event) => setSelectedItemId(event.target.value)}
                size={Math.min(6, Math.max(3, filteredItems.length))}
              >
                {filteredItems.map((item) => (
                  <option key={item['Item ID']} value={item['Item ID']}>
                    {item['Display Name']}
                  </option>
                ))}
              </select>
            )}
            <div className="button-row">
              <button
                type="button"
                className="btn primary"
                disabled={!selectedItemId || filteredItems.length === 0}
                onClick={grantSelectedItem100}
              >
                Add 100 items
              </button>
              <button type="button" className="btn secondary" onClick={clearAllItems}>
                Clear items
              </button>
            </div>
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
            Demo aids: raise/reset skills, grant or clear items, plus quick mats for food, mining,
            production, smithing, and Arcana. Clear items empties inventory and equipment.
          </p>
        </div>
      )}
    </section>
  )
}
