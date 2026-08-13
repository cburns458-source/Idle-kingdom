import { useEffect, useMemo, useRef, useState } from 'react'
import { validateActivityStart } from './game/activity/engine'
import {
  requestActivityStart,
  requestActivityStop,
  requestProductionStart,
} from './game/activity/transition'
import { loadDatabase, type LoadedDatabase } from './game/data/loadDatabase'
import type { ActionRewardBundle } from './game/activity/types'
import type { ActivityRow } from './game/data/types'
import { advanceSession } from './game/session/tick'
import { actionProgressAt } from './game/session/progress'
import { prepareSaveForWrite } from './game/session/persist'
import { arriveFromTravel, planTravel, type TravelArrival } from './game/session/travel'
import type { SessionEvent } from './game/session/events'
import { loadOrCreateSave, writeSave } from './game/save/saveStore'
import type { PlayerSave } from './game/save/types'
import { CITADEL_MAP_ID, CITADEL_MARKET_ID, CITADEL_PLAZA_ID, MAIN_MAP_ID } from './game/world/constants'
import { claimLocationSearch } from './game/world/locationSearch'
import {
  enterSubMapLabel,
  isSubMap,
  subMapIdForGateway,
} from './game/world/submaps'
import { resolveActiveMapId } from './game/world/travel'
import { configNumber } from './game/activity/gathering'
import { deathPauseRemainingMs, getEnemy, isDeathPaused } from './game/combat/engine'
import { playerMaxHp } from './game/combat/stats'
import { addItemToInventory } from './game/activity/rewards'
import {
  applyAutoEquipProposal,
  proposeAutoEquipForActivity,
  type AutoEquipProposal,
} from './game/equipment/autoEquip'
import { withRecalculatedVitals } from './game/equipment/vitals'
import { getRecipe, isStandardProductionActivity } from './game/production/recipes'
import { syncProgressionMeta } from './game/achievements/progress'
import { spawnCritterAtLocation } from './game/critters/critters'
import { cosmeticById } from './game/cosmetics/cosmetics'
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
import { ChatDrawer } from './ui/ChatDrawer'
import { AccountPanel } from './ui/AccountPanel'
import { InventoryView } from './ui/InventoryView'
import { CitadelHubPanel, type CitadelHubTab } from './ui/CitadelHubPanel'
import { LocationView } from './ui/LocationView'
import { CITADEL_LOCATION_ID } from './game/multiplayer/types'
import { LogView } from './ui/LogView'
import { SocialView } from './ui/SocialView'
import { getSession } from './game/multiplayer/auth'
import { pushCloudSave } from './game/multiplayer/cloudSave'
import { NamePrompt } from './ui/NamePrompt'
import { NewCharacterFlow, RaceOnlyPicker } from './ui/NewCharacterFlow'
import { assignRace } from './game/races/assignRace'
import { raceDisplayName } from './game/races/races'
import { NpcPanel } from './ui/NpcPanel'
import { ProductionPicker, ProductionProgress } from './ui/ProductionPanel'
import { AutoEquipPrompt } from './ui/AutoEquipPrompt'
import { ProjectCompletePopup } from './ui/ProjectCompletePopup'
import { ProjectPicker } from './ui/ProjectPanel'
import { getProject } from './game/projects/projects'
import { ShopPanel } from './ui/ShopPanel'
import { SkillsView } from './ui/SkillsView'
import { ActionRewardList } from './ui/ActionRewardList'
import { TopHud, type HudActivityStatus } from './ui/TopHud'
import { TravelOverlay } from './ui/TravelOverlay'
import { WardrobeModal } from './ui/WardrobeModal'
import { WardrobeUnlockPopup } from './ui/WardrobeUnlockPopup'
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
  const [hudNowMs, setHudNowMs] = useState(() => Date.now())
  const [lastMessage, setLastMessage] = useState<string | null>(null)
  const [lastPlayerHit, setLastPlayerHit] = useState<number | null>(null)
  const [lastPlayerCrit, setLastPlayerCrit] = useState(false)
  const [lastOffhandHit, setLastOffhandHit] = useState<number | null>(null)
  const [lastEnemyHit, setLastEnemyHit] = useState<number | null>(null)
  const [defeatedFlash, setDefeatedFlash] = useState(false)
  const [pauseRemainingMs, setPauseRemainingMs] = useState(0)
  const [renamingCharacter, setRenamingCharacter] = useState(false)
  const [changingRace, setChangingRace] = useState(false)
  const [productionPickerActivityId, setProductionPickerActivityId] = useState<string | null>(null)
  const [specialStation, setSpecialStation] = useState<SpecialProductionStation | null>(null)
  const [activeShopId, setActiveShopId] = useState<string | null>(null)
  const [activeNpcId, setActiveNpcId] = useState<string | null>(null)
  const [activeCitadelHub, setActiveCitadelHub] = useState<CitadelHubTab | null>(null)
  const [afkSummary, setAfkSummary] = useState<AfkSummaryData | null>(null)
  const [projectCompletePopup, setProjectCompletePopup] = useState<{
    projectName: string
    lines: string[]
  } | null>(null)
  const [craftPopup, setCraftPopup] = useState<{
    itemId: string
    name: string
    key: number
  } | null>(null)
  const [autoEquipPrompt, setAutoEquipPrompt] = useState<AutoEquipProposal | null>(null)
  const [wardrobeOpen, setWardrobeOpen] = useState(false)
  const [wardrobeUnlockPopup, setWardrobeUnlockPopup] = useState<{
    cosmeticId: string
    isFirstEver: boolean
  } | null>(null)
  const bootRef = useRef(boot)
  bootRef.current = boot

  useEffect(() => {
    if (!activityError) return
    const timer = window.setTimeout(() => setActivityError(null), 2000)
    return () => window.clearTimeout(timer)
  }, [activityError])

  useEffect(() => {
    if (!craftPopup) return
    const timer = window.setTimeout(() => setCraftPopup(null), 2000)
    return () => window.clearTimeout(timer)
  }, [craftPopup])

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
          setBrowseMapId(location ? resolveActiveMapId(database.launch, location) : MAIN_MAP_ID)
          setSelectedLocationId(nextSave.currentLocationId)
          if (resolved.messages[0]) setLastMessage(resolved.messages[0]!)
          const hadAfkProgress =
            resolved.gatheringActions > 0 ||
            resolved.craftsCompleted > 0 ||
            resolved.combatVictories > 0 ||
            resolved.combatDeaths > 0 ||
            resolved.crittersSpawned > 0
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
        const arrival = arriveFromTravel(current.database.launch, current.save, travel.toLocationId)
        const saved = persistSave(arrival.save)
        setBoot({ ...current, save: saved, saveCreated: false })
        showArrival(current.database, arrival, saved.currentLocationId)
        setActionProgress(0)
        setTravel(null)
        setTravelProgress(0)
        return
      }
      frame = window.requestAnimationFrame(tick)
    }

    frame = window.requestAnimationFrame(tick)
    return () => window.cancelAnimationFrame(frame)
  }, [travel, boot.status])

  const runningActivityId = boot.status === 'ready' ? boot.save.currentActivityId : null
  const runningProductionRecipeId = boot.status === 'ready' ? boot.save.productionRecipeId : null

  // Keep HUD activity timers current while something is running.
  useEffect(() => {
    if (!runningActivityId && !runningProductionRecipeId) return
    setHudNowMs(Date.now())
    const id = window.setInterval(() => setHudNowMs(Date.now()), 250)
    return () => window.clearInterval(id)
  }, [runningActivityId, runningProductionRecipeId])

  /** Shows an arrival: the destination's map, and whatever hostility had to say. */
  function showArrival(
    database: LoadedDatabase,
    arrival: TravelArrival,
    locationId: string,
  ) {
    const location = database.launchIndexes.locationsById.get(locationId)
    setBrowseMapId(location ? resolveActiveMapId(database.launch, location) : MAIN_MAP_ID)
    setSelectedLocationId(locationId)
    setScreen('location')
    setRecentRewards([])
    setLastMessage(arrival.forcedActivityId ? arrival.message : null)
    setActivityError(arrival.blockedReason ? arrival.message : null)
  }

  /** Reflects one tick's events in the screen state they drive. */
  function applySessionEvents(events: SessionEvent[]) {
    for (const event of events) {
      switch (event.kind) {
        case 'rewards':
          setRecentRewards((prev) => [event.bundle, ...prev].slice(0, 4))
          setLastMessage(null)
          break
        case 'message':
          setLastMessage(event.text)
          break
        case 'activity-stopped':
          setActivityError(event.reason)
          break
        case 'craft-completed':
          setActivityError(null)
          setCraftPopup({ itemId: event.itemId, name: event.displayName, key: Date.now() })
          break
        case 'inventory-full':
          setActivityError('Inventory full — free space to continue crafting.')
          break
        case 'combat-round':
          setLastPlayerHit(event.playerHit)
          setLastPlayerCrit(event.playerCrit)
          setLastOffhandHit(event.offhandHit)
          setLastEnemyHit(event.enemyHit)
          break
        case 'enemy-defeated':
          setDefeatedFlash(true)
          break
        case 'recovered':
          setLastMessage('Recovered. Resuming activity…')
          break
        // A death already reads off the save (HP, pause) and a spawn is picked up
        // by the critter panel, so neither needs its own screen state.
        case 'player-defeated':
        case 'critter-spawned':
          break
      }
    }
  }

  // Everything the save has due — a gathering action, a craft, a combat round,
  // a death-pause recovery, or the next action for an activity that has none —
  // is advanced by the headless session, so this loop only draws and reacts.
  useEffect(() => {
    if (boot.status !== 'ready' || travel) return

    let frame = 0
    const tick = () => {
      const current = bootRef.current
      if (current.status === 'ready') {
        const now = Date.now()
        setPauseRemainingMs(deathPauseRemainingMs(current.save, now))
        setActionProgress(actionProgressAt(current.save, now))

        const advanced = advanceSession(current.database.launch, current.save, now)
        if (advanced.changed) {
          applySessionEvents(advanced.events)
          setBoot({ ...current, save: persistSave(advanced.save), saveCreated: false })
        }
      }
      frame = window.requestAnimationFrame(tick)
    }

    frame = window.requestAnimationFrame(tick)
    return () => window.cancelAnimationFrame(frame)
    // The loop reads the live save through `bootRef`, so it only has to be
    // rebuilt when the game becomes playable or travel takes over.
  }, [boot.status, travel])

  const ready = boot.status === 'ready' ? boot : null

  // Both totals walk every skill, and the skill list is replaced only when xp
  // actually lands, so keying on it skips the walk on the frames in between.
  const skills = ready?.save.skills
  const overallXp = useMemo(() => (skills ? totalSkillXp({ skills }) : 0), [skills])
  const overallLevel = useMemo(() => (skills ? totalLevel({ skills }) : 0), [skills])

  function persistSave(next: PlayerSave): PlayerSave {
    const current = bootRef.current
    return writeSave(
      current.status === 'ready'
        ? prepareSaveForWrite(current.database.launch, next)
        : stampUnattendedProgressAt(next),
    )
  }

  // A kill flashes "defeated" over the panel. The rewards and the next enemy are
  // already applied by the tick that resolved the round, so this only clears the
  // flash and the round's hit numbers once it has been seen.
  // Must stay above early returns so hook order is stable while boot loads.
  useEffect(() => {
    if (!defeatedFlash) return
    const timer = window.setTimeout(() => {
      setDefeatedFlash(false)
      setLastPlayerHit(null)
      setLastPlayerCrit(false)
      setLastOffhandHit(null)
      setLastEnemyHit(null)
    }, 750)
    return () => window.clearTimeout(timer)
  }, [defeatedFlash])

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

  let hudActivityStatus: HudActivityStatus = null
  if (inProduction && productionRecipe) {
    const total = save.productionQuantityTotal ?? 0
    const remaining = save.productionQuantityRemaining ?? 0
    const completed = Math.max(0, total - remaining)
    const craftSeconds = Math.max(0, (save.actionDurationMs ?? 0) / 1000)
    const craftRemainingSeconds = Math.max(0, craftSeconds * (1 - actionProgress))
    const upcomingCrafts = Math.max(0, remaining - (remaining > 0 ? 1 : 0))
    hudActivityStatus = {
      kind: 'production',
      itemName: productionRecipe['Display Name'],
      completed,
      total,
      remainingSeconds: craftRemainingSeconds + upcomingCrafts * craftSeconds,
    }
  } else if (activity) {
    const startedAtMs = save.activityStartedAt
      ? Date.parse(save.activityStartedAt)
      : Number.NaN
    const elapsedSeconds = Number.isFinite(startedAtMs)
      ? Math.max(0, (hudNowMs - startedAtMs) / 1000)
      : 0
    const actionName = inCombat
      ? (combatEnemy?.['Display Name'] ?? currentAction?.['Display Name'] ?? 'Combat')
      : (currentAction?.['Display Name'] ?? '…')
    hudActivityStatus = {
      kind: 'action',
      activityName: activity['Contextual Name'] ?? activity['Internal Key'],
      actionName,
      elapsedSeconds,
    }
  }
  const pickerActivity = productionPickerActivityId
    ? database.launchIndexes.activitiesById.get(productionPickerActivityId)
    : undefined
  // Shop/NPC/Special Production/Standard Production browsing always takes
  // over the status-panel slot, replacing whatever live activity panel
  // (combat, production progress, gathering, recovery) would otherwise show
  // underneath — browsing never stops the running Primary Activity, it just
  // temporarily covers its panel. See docs/Game_Bible.txt section 9.1.
  const browsePanelOpen = Boolean(
    activeShopId || activeNpcId || activeCitadelHub || specialStation || pickerActivity,
  )

  const fromLocation = database.launchIndexes.locationsById.get(
    travel?.fromLocationId ?? save.currentLocationId,
  )
  const toLocation = database.launchIndexes.locationsById.get(travel?.toLocationId ?? '')

  function updateSave(next: PlayerSave) {
    const saved = persistSave(next)
    setBoot((bootState) =>
      bootState.status === 'ready'
        ? { ...bootState, save: saved, saveCreated: false }
        : bootState,
    )
  }

  const deathLocked = isDeathPaused(save) || pauseRemainingMs > 0

  function beginTravel(destinationId: string) {
    if (travel) return
    const now = Date.now()
    const plan = planTravel(database.launch, save, destinationId, browseMapId, now)
    if (plan.kind === 'blocked') return

    setProductionPickerActivityId(null)
    setSpecialStation(null)
    setActiveShopId(null)
    setActiveNpcId(null)
    setActiveCitadelHub(null)
    setActionProgress(0)

    if (plan.kind === 'instant') {
      updateSave(plan.arrival.save)
      showArrival(database, plan.arrival, destinationId)
      setTravel(null)
      setTravelProgress(0)
      return
    }

    if (plan.save !== save) updateSave(plan.save)
    setRecentRewards([])
    setTravel({
      fromLocationId: save.currentLocationId,
      toLocationId: destinationId,
      startedAt: now,
      durationMs: plan.durationMs,
    })
    setTravelProgress(0)
  }

  function startActivity(
    activityId: string,
    fromSave: PlayerSave = save,
    allowAutoEquipPrompt = true,
  ) {
    const activityRow = database.launchIndexes.activitiesById.get(activityId)
    const isProduction =
      Boolean(activityRow) && isStandardProductionActivity(database.launch, activityRow!)

    // Recipe browsing stays available during death pause; Primary Activity changes do not.
    if (deathLocked && !isProduction) {
      setActivityError('Cannot change activities while recovering from defeat.')
      return
    }

    const result = validateActivityStart(database.launch, fromSave, activityId)
    if (!result.ok) {
      if (allowAutoEquipPrompt && !deathLocked) {
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

    if (isProduction) {
      setSpecialStation(null)
      setProductionPickerActivityId(activityId)
      if (fromSave !== save) updateSave(fromSave)
      return
    }
    setSpecialStation(null)
    setProductionPickerActivityId(null)

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
    // Browse/complete Special Production during death pause; do not force-close the picker.
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

  function syncCloudIfSignedIn(next: PlayerSave) {
    if (!getSession()) return
    void pushCloudSave(database.launch, next)
  }

  function stopActivity() {
    if (deathLocked) return
    setActivityError(null)
    setActionProgress(0)
    setLastMessage(null)
    setLastPlayerHit(null)
    setLastPlayerCrit(false)
    setLastOffhandHit(null)
    setLastEnemyHit(null)
    setDefeatedFlash(false)
    setProductionPickerActivityId(null)
    setSpecialStation(null)
    const requested = requestActivityStop(database.launch, save)
    if (!requested.ok) {
      setActivityError(requested.reason)
      return
    }
    updateSave(requested.save)
    syncCloudIfSignedIn(requested.save)
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
          appearance={save.appearance}
          raceName={raceDisplayName(database.launch, save.raceId)}
          totalLevel={overallLevel}
          totalXp={overallXp}
          showTotalXp={save.settings.hudShowTotalXp === true}
          onToggleTotalStat={() => {
            const current = bootRef.current
            if (current.status !== 'ready') return
            updateSave({
              ...current.save,
              settings: {
                ...current.save.settings,
                hudShowTotalXp: current.save.settings.hudShowTotalXp !== true,
              },
            })
          }}
          gold={save.gold}
          currentHp={save.currentHp}
          maxHp={maxHp}
          dead={deathLocked}
          activityStatus={hudActivityStatus}
          onOpenWardrobe={() => {
            setWardrobeOpen(true)
            if (!save.hasSeenWardrobeIntro) {
              updateSave({ ...save, hasSeenWardrobeIntro: true })
            }
          }}
          wardrobeHint={!save.hasSeenWardrobeIntro && save.cosmetics.unlocked.length > 0}
        />

        <div className={screen === 'map' ? 'screen-body screen-body-map' : 'screen-body'}>
          {screen === 'location' && (
            <LocationView
              indexes={database.launchIndexes}
              db={database.launch}
              location={location}
              save={save}
              currentActivityId={save.currentActivityId}
              activityError={activityError}
              requirementHint={requirementHint}
              isRecipeBrowserActivity={(row) =>
                isStandardProductionActivity(database.launch, row)
              }
              actionsLocked={deathLocked}
              rewardSummary={
                <ActionRewardList
                  rewards={recentRewards}
                  itemsById={database.launchIndexes.itemsById}
                  compact
                  hidden={save.settings.showActivityRewards === false}
                />
              }
              onStartActivity={startActivity}
              onStopActivity={stopActivity}
              onCollectCritter={(next, message) => {
                updateSave(next)
                setLastMessage(message)
              }}
              onSearchLocation={(searchId) => {
                const result = claimLocationSearch(database.launch, save, searchId)
                if (result.ok) {
                  updateSave(result.save)
                  setLastMessage(`Found a ${result.itemName}!`)
                } else if (result.reason) {
                  setLastMessage(result.reason)
                }
              }}
              onOpenSpecialProduction={(station) => {
                setActiveShopId(null)
                setActiveNpcId(null)
                setActiveCitadelHub(null)
                openSpecialProduction(station)
              }}
              onOpenShop={(shopId) => {
                setSpecialStation(null)
                setProductionPickerActivityId(null)
                setActiveNpcId(null)
                setActiveCitadelHub(null)
                setActiveShopId(shopId)
              }}
              onOpenNpc={(npcId) => {
                setSpecialStation(null)
                setProductionPickerActivityId(null)
                setActiveShopId(null)
                setActiveCitadelHub(null)
                setActiveNpcId(npcId)
              }}
              onOpenCitadelHub={
                save.currentLocationId === CITADEL_PLAZA_ID ||
                save.currentLocationId === CITADEL_MARKET_ID ||
                save.currentLocationId === CITADEL_LOCATION_ID
                  ? (tab) => {
                      setSpecialStation(null)
                      setProductionPickerActivityId(null)
                      setActiveShopId(null)
                      setActiveNpcId(null)
                      setActiveCitadelHub(tab)
                    }
                  : undefined
              }
              citadelHubTabs={
                save.currentLocationId === CITADEL_PLAZA_ID ||
                save.currentLocationId === CITADEL_LOCATION_ID
                  ? ['bounties']
                  : save.currentLocationId === CITADEL_MARKET_ID
                    ? ['bazaar']
                    : []
              }
              citadelHubTitle={
                save.currentLocationId === CITADEL_MARKET_ID ? 'Market District' : 'Citadel Plaza'
              }
              onOpenMap={() => {
                setBrowseMapId(MAIN_MAP_ID)
                setSelectedLocationId(save.currentLocationId)
                setScreen('map')
              }}
              enterSubMapLabelText={enterSubMapLabel(database.launch, location)}
              onOpenSubMap={() => {
                const childMap = subMapIdForGateway(database.launch, save.currentLocationId)
                if (childMap) setBrowseMapId(childMap)
                setSelectedLocationId(save.currentLocationId)
                setScreen('map')
              }}
              parentSubMapName={
                isSubMap(database.launch, location['Map ID'])
                  ? (database.launch.Maps.find((map) => map['Map ID'] === location['Map ID'])?.[
                      'Display Name'
                    ] ?? 'Sub-map')
                  : null
              }
              onOpenParentSubMap={
                isSubMap(database.launch, location['Map ID'])
                  ? () => {
                      setBrowseMapId(location['Map ID']!)
                      setSelectedLocationId(save.currentLocationId)
                      setScreen('map')
                    }
                  : undefined
              }
              skillNameForId={(skillId) =>
                skillId
                  ? (database.launch.Skills.find((skill) => skill['Skill ID'] === skillId)?.[
                      'Display Name'
                    ] ?? skillId)
                  : 'Skill'
              }
              statusPanel={
                <>
                  {activeShopId && (
                    <ShopPanel
                      db={database.launch}
                      save={save}
                      shopId={activeShopId}
                      onClose={() => setActiveShopId(null)}
                      onComplete={(next, message, cosmeticsGranted) => {
                        updateSave(next)
                        setLastMessage(message)
                        if (cosmeticsGranted.length > 0) {
                          const grant = cosmeticsGranted[0]!
                          setWardrobeUnlockPopup({
                            cosmeticId: grant.cosmeticId,
                            isFirstEver: grant.isFirstEver,
                          })
                        }
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
                  {activeCitadelHub && (
                    <CitadelHubPanel
                      tab={activeCitadelHub}
                      db={database.launch}
                      save={save}
                      onChangeSave={updateSave}
                      onClose={() => setActiveCitadelHub(null)}
                      onMessage={setLastMessage}
                      onOpenGuilds={() => {
                        setActiveCitadelHub(null)
                        setScreen('guilds')
                      }}
                    />
                  )}
                  {specialStation && !activeShopId && !activeNpcId && !activeCitadelHub && (
                    <ProjectPicker
                      db={database.launch}
                      save={save}
                      station={specialStation}
                      onCancel={() => setSpecialStation(null)}
                      onConfirm={confirmSpecialProject}
                    />
                  )}
                  {pickerActivity &&
                    !specialStation &&
                    !activeShopId &&
                    !activeNpcId &&
                    !activeCitadelHub && (
                    <ProductionPicker
                      db={database.launch}
                      save={save}
                      activity={pickerActivity}
                      onCancel={() => setProductionPickerActivityId(null)}
                      onConfirm={confirmProduction}
                    />
                  )}
                  {activity && inCombat && combatEnemy && !browsePanelOpen && (
                    <CombatPanel
                      enemy={combatEnemy}
                      enemyHp={save.combatEnemyHp ?? combatEnemy['Maximum HP']}
                      playerHp={save.currentHp}
                      playerMaxHp={maxHp}
                      appearance={save.appearance}
                      roundStartedAt={save.combatRoundStartedAt}
                      roundDurationMs={
                        configNumber(database.launch, 'combat_round_duration', 4) * 1000
                      }
                      lastPlayerHit={lastPlayerHit}
                      lastPlayerCrit={lastPlayerCrit}
                      lastOffhandHit={lastOffhandHit}
                      lastEnemyHit={lastEnemyHit}
                      defeatedFlash={defeatedFlash}
                      deathPauseRemainingMs={pauseRemainingMs}
                    />
                  )}
                  {activity &&
                    inProduction &&
                    productionRecipe &&
                    pauseRemainingMs <= 0 &&
                    !browsePanelOpen && (
                    <ProductionProgress
                      db={database.launch}
                      activity={activity}
                      recipe={productionRecipe}
                      save={save}
                      progress={actionProgress}
                      onStop={stopActivity}
                      craftPopup={craftPopup}
                    />
                  )}
                  {activity &&
                    !inCombat &&
                    !inProduction &&
                    pauseRemainingMs <= 0 &&
                    !browsePanelOpen && (
                      <ActivityPanel
                        activity={activity}
                        action={currentAction ?? null}
                        save={save}
                        skill={actionSkill}
                        progress={actionProgress}
                        durationMs={save.actionDurationMs}
                      />
                    )}
                  {activity &&
                    pauseRemainingMs > 0 &&
                    !inCombat &&
                    !browsePanelOpen && (
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
              save={save}
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
          {screen === 'log' && <LogView save={save} database={database} />}
          {screen === 'leaderboards' && (
            <SocialView save={save} database={database} section="leaderboards" />
          )}
          {screen === 'guilds' && (
            <SocialView
              save={save}
              database={database}
              section="guilds"
              onChangeSave={updateSave}
            />
          )}
          {screen === 'citadel' && (
            <SocialView save={save} database={database} section="citadel" />
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
              changingRace={changingRace}
              onStartChangeRace={() => setChangingRace(true)}
              onCancelChangeRace={() => setChangingRace(false)}
              onChangeRace={(raceId) => {
                const assigned = assignRace(database.launch, save, raceId)
                if (assigned.ok) {
                  updateSave(assigned.save)
                  setLastMessage(
                    `Race changed to ${raceDisplayName(database.launch, raceId)} (test).`,
                  )
                }
                setChangingRace(false)
              }}
              onPreviewAfkSummary={() => setAfkSummary(exampleAfkSummary())}
              onSpawnCritter={() => {
                const result = spawnCritterAtLocation(save, save.currentLocationId)
                if (!result.ok) {
                  setLastMessage(result.reason)
                  return
                }
                updateSave(result.save)
                setLastMessage(`${result.critter.displayName} appeared nearby.`)
                setScreen('location')
              }}
              onOpenSocial={() => setScreen('leaderboards')}
              onMessage={setLastMessage}
            />
          )}
        </div>

        <ChatDrawer
          locationId={save.currentLocationId}
          citadelHubChat={resolveActiveMapId(database.launch, location) === CITADEL_MAP_ID}
        />

        <BottomNav
          screen={screen}
          onChange={setScreen}
          currentLocationName={location['Display Name']}
          onOpenMainMap={() => {
            setBrowseMapId(MAIN_MAP_ID)
            setSelectedLocationId(save.currentLocationId)
            setScreen('map')
          }}
        />

        {travel && fromLocation && toLocation && (
          <TravelOverlay
            fromName={fromLocation['Display Name']}
            toName={toLocation['Display Name']}
            progress={travelProgress}
          />
        )}

        {!save.characterName && (
          <div className="name-prompt-overlay">
            <NewCharacterFlow
              db={database.launch}
              initialAppearance={save.appearance}
              onComplete={(name, raceId, appearance) => {
                const assigned = assignRace(
                  database.launch,
                  { ...save, characterName: name, appearance },
                  raceId,
                )
                if (assigned.ok) updateSave(assigned.save)
              }}
            />
          </div>
        )}

        {save.characterName && !save.raceId && (
          <div className="name-prompt-overlay">
            <RaceOnlyPicker
              db={database.launch}
              title="Choose your race"
              lead="Existing adventurers must pick a race once before continuing."
              submitLabel="Confirm race"
              showStartingItems
              onComplete={(raceId) => {
                const assigned = assignRace(database.launch, save, raceId)
                if (assigned.ok) {
                  updateSave(assigned.save)
                  setLastMessage(
                    assigned.grantedStarterKit
                      ? `You are now a ${raceDisplayName(database.launch, raceId)}.`
                      : null,
                  )
                }
              }}
            />
          </div>
        )}

        <WardrobeModal
          db={database.launch}
          save={save}
          open={wardrobeOpen}
          onClose={() => setWardrobeOpen(false)}
          onChangeSave={updateSave}
        />

        {wardrobeUnlockPopup &&
          (() => {
            const cosmetic = cosmeticById(database.launch, wardrobeUnlockPopup.cosmeticId)
            const item = cosmetic
              ? database.launch.Items.find((row) => row['Item ID'] === cosmetic['Item ID'])
              : undefined
            return (
              <WardrobeUnlockPopup
                cosmeticName={item?.['Display Name'] ?? 'New Cosmetic'}
                item={item}
                isFirstEver={wardrobeUnlockPopup.isFirstEver}
                onClose={() => setWardrobeUnlockPopup(null)}
              />
            )
          })()}

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
  changingRace,
  onStartChangeRace,
  onCancelChangeRace,
  onChangeRace,
  onPreviewAfkSummary,
  onSpawnCritter,
  onOpenSocial,
  onMessage,
}: {
  save: PlayerSave
  database: LoadedDatabase
  onChangeSave: (save: PlayerSave) => void
  renaming: boolean
  onStartRename: () => void
  onCancelRename: () => void
  onRename: (name: string) => void
  changingRace: boolean
  onStartChangeRace: () => void
  onCancelChangeRace: () => void
  onChangeRace: (raceId: string) => void
  onPreviewAfkSummary: () => void
  onSpawnCritter: () => void
  onOpenSocial: () => void
  onMessage: (message: string) => void
}) {
  const launchSkills = database.launch.Skills
  const launchItems = database.launch.Items
  const levelCap = configNumber(database.launch, 'display_level_cap', 100)

  const [selectedSkillId, setSelectedSkillId] = useState(
    launchSkills[0]?.['Skill ID'] ?? 'SKL-0001',
  )
  const [itemSearch, setItemSearch] = useState('')
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

  function clearGold() {
    onChangeSave({ ...save, gold: 0, updatedAt: new Date().toISOString() })
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

  if (changingRace) {
    return (
      <RaceOnlyPicker
        db={database.launch}
        title="Change race (test)"
        lead="Temporary testing control. A future repeatable quest will replace this."
        submitLabel="Change race"
        showStartingItems={false}
        onComplete={onChangeRace}
        onCancel={onCancelChangeRace}
      />
    )
  }

  return (
    <section className="panel menu-panel">
      <h1>Menu</h1>
      <div className="menu-tab-panel">
        <p className="lead">Settings and temporary demo aids.</p>

        <div className="menu-name-block">
          <p className="muted tiny">Character</p>
          <p className="lead">{save.characterName ?? 'Unnamed'}</p>
          <p className="muted tiny">
            Race: {raceDisplayName(database.launch, save.raceId) ?? 'Unchosen'}
          </p>
          <button type="button" className="btn secondary" onClick={onStartRename}>
            Change name
          </button>
          <button type="button" className="btn secondary" onClick={onStartChangeRace}>
            Change race (test)
          </button>
        </div>

        <AccountPanel
          db={database.launch}
          save={save}
          onChangeSave={onChangeSave}
          onOpenSocial={onOpenSocial}
          onMessage={onMessage}
        />

        <div className="menu-demo-block">
          <p className="muted tiny">Activity rewards</p>
          <p className="muted tiny">
            Show the recent reward summary on the location background.
          </p>
          <button
            type="button"
            className="btn secondary"
            onClick={() =>
              onChangeSave({
                ...save,
                settings: {
                  ...save.settings,
                  showActivityRewards: save.settings.showActivityRewards === false,
                },
                updatedAt: new Date().toISOString(),
              })
            }
          >
            {save.settings.showActivityRewards === false
              ? 'Show activity rewards'
              : 'Hide activity rewards'}
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
          <p className="muted tiny">Critters</p>
          <p className="muted tiny">
            Spawn the habitat Critter at your current location when one is available and none is
            waiting.
          </p>
          <button type="button" className="btn secondary" onClick={onSpawnCritter}>
            Spawn Critter
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
          <button type="button" className="btn secondary" onClick={clearGold}>
            Clear gold
          </button>
        </div>
        <p className="muted tiny">
          Demo aids: raise/reset skills, grant or clear items, and clear gold. Clear items empties
          inventory and equipment.
        </p>
      </div>
    </section>
  )
}
