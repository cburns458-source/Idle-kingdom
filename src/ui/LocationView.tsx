import {
  Children,
  Fragment,
  isValidElement,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from 'react'
import { locationAssetPath, uiMapAssetPath } from '../game/assets/assetMap'
import type { ActivityRow, DatabaseIndexes, GameDatabase, LocationRow } from '../game/data/types'
import {
  specialProductionStationsAt,
  type SpecialProductionStation,
} from '../game/projects/projects'
import { enterSubMapLabel, isSubMapGateway } from '../game/world/submaps'
import {
  canClaimLocationSearch,
  locationSearchCooldownRemainingMs,
} from '../game/world/locationSearch'
import { isSignedIn } from '../game/multiplayer/auth'
import type { PlayerSave } from '../game/save/types'
import { ActivePlayersPanel } from './ActivePlayersPanel'
import { CritterOverlay } from './CritterOverlay'
import { formatDurationSeconds } from './formatDuration'

/**
 * True when a ReactNode will actually mount visible UI. App.tsx always
 * passes `statusPanel` as a `<>...</>` fragment (even when every conditional
 * child inside is false), so a plain `Boolean(statusPanel)`/truthy check is
 * always true and would render an empty wrapper. Walk fragments to find out
 * whether there's real content inside.
 */
export function hasRenderableContent(node: ReactNode): boolean {
  if (node == null || typeof node === 'boolean') return false
  if (typeof node === 'string') return node.trim().length > 0
  if (typeof node === 'number') return true
  if (Array.isArray(node)) return node.some(hasRenderableContent)
  if (isValidElement(node)) {
    if (node.type === Fragment) {
      return hasRenderableContent((node.props as { children?: ReactNode }).children)
    }
    // Treat any real element as content; individual panels are responsible
    // for not rendering an empty fragment themselves once they're mounted.
    return true
  }
  return Children.count(node) > 0
}

interface LocationViewProps {
  indexes: DatabaseIndexes
  db: GameDatabase
  location: LocationRow
  save: PlayerSave
  currentActivityId: string | null
  activityError: string | null
  actionsLocked?: boolean
  statusPanel?: ReactNode
  /** Activity reward summary rendered on the location background. */
  rewardSummary?: ReactNode
  onStartActivity: (activityId: string) => void
  onStopActivity: () => void
  onOpenSpecialProduction: (station: SpecialProductionStation) => void
  onOpenShop: (shopId: string) => void
  onOpenNpc: (npcId: string) => void
  onOpenMap: () => void
  onOpenSubMap?: () => void
  /** CTA label for entering this location's child sub-map. */
  enterSubMapLabelText?: string | null
  /** When set, show a control to reopen this location's sub-map. */
  parentSubMapName?: string | null
  onOpenParentSubMap?: () => void
  onCollectCritter: (save: PlayerSave, message: string) => void
  onSearchLocation: (searchId: string) => void
  requirementHint?: (activity: ActivityRow) => string | null
  /** Standard Production opens a recipe picker. */
  isRecipeBrowserActivity?: (activity: ActivityRow) => boolean
  /** Skill label helper for the Nearby Adventurers panel. */
  skillNameForId?: (skillId: string | null) => string
}

function MapIcon() {
  return (
    <span
      className="map-icon map-icon-pixel"
      style={{ backgroundImage: `url(${uiMapAssetPath()})` }}
      aria-hidden
    />
  )
}

function NearbyPlayersIcon() {
  return (
    <svg className="map-icon nearby-players-svg" viewBox="0 0 24 24" aria-hidden>
      <circle cx="9" cy="8" r="3.2" fill="currentColor" />
      <circle cx="16.5" cy="9" r="2.6" fill="currentColor" opacity="0.85" />
      <path
        d="M3.5 18.5c.6-3.2 2.8-5 5.5-5s4.9 1.8 5.5 5"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
      />
      <path
        d="M13.2 18.5c.35-1.9 1.5-3.1 3.3-3.1 1.7 0 2.9 1.1 3.3 3.1"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinecap="round"
        opacity="0.85"
      />
    </svg>
  )
}

export function LocationView({
  indexes,
  db,
  location,
  save,
  currentActivityId,
  activityError,
  actionsLocked = false,
  statusPanel,
  rewardSummary,
  onStartActivity,
  onStopActivity,
  onOpenSpecialProduction,
  onOpenShop,
  onOpenNpc,
  onOpenMap,
  onOpenSubMap,
  enterSubMapLabelText,
  parentSubMapName,
  onOpenParentSubMap,
  onCollectCritter,
  onSearchLocation,
  requirementHint,
  isRecipeBrowserActivity,
  skillNameForId,
}: LocationViewProps) {
  const locationId = location['Location ID']
  const activities = indexes.activitiesByLocationId.get(locationId) ?? []
  const specialStations = specialProductionStationsAt(db, locationId)
  const shops = indexes.shopsByLocationId.get(locationId) ?? []
  const npcs = indexes.npcsByLocationId.get(locationId) ?? []
  const searchSpots = indexes.locationSearchesByLocationId.get(locationId) ?? []
  const [nowTick, setNowTick] = useState(() => Date.now())
  const [nearbyOpen, setNearbyOpen] = useState(false)
  const signedIn = isSignedIn()
  const resolveSkillName =
    skillNameForId ??
    ((skillId: string | null) =>
      skillId
        ? (db.Skills.find((skill) => skill['Skill ID'] === skillId)?.['Display Name'] ?? skillId)
        : 'Skill')
  const gatewayLabel =
    enterSubMapLabelText ?? enterSubMapLabel(db, location)
  const showSubMapEntrance =
    Boolean(onOpenSubMap) && isSubMapGateway(location) && Boolean(gatewayLabel)
  const showBackToSubMap =
    Boolean(onOpenParentSubMap) && Boolean(parentSubMapName) && !showSubMapEntrance
  const showActivityPanel =
    !showSubMapEntrance && (activities.length > 0 || specialStations.length > 0)
  const shadeRef = useRef<HTMLDivElement | null>(null)
  const hasStatusPanel = hasRenderableContent(statusPanel)

  useEffect(() => {
    if (searchSpots.length === 0) return
    const interval = window.setInterval(() => setNowTick(Date.now()), 30_000)
    return () => window.clearInterval(interval)
  }, [searchSpots.length])

  function scrollLocationToTop() {
    const shade = shadeRef.current
    if (!shade) return
    // Wait a frame so status panels (shop / NPC / activity) can mount first.
    requestAnimationFrame(() => {
      shade.scrollTo({ top: 0, behavior: 'smooth' })
    })
  }

  return (
    <>
    <section
      className="location-view"
      style={{ backgroundImage: `url(${locationAssetPath(locationId)})` }}
    >
      <CritterOverlay save={save} locationId={locationId} onCollect={onCollectCritter} />
      <div className="location-view-shade" ref={shadeRef}>
        <header className="location-overlay-head">
          <div className="location-overlay-copy">
            <h1>{location['Display Name']}</h1>
            <p className="location-description">
              {location.Description ?? 'Explore this place.'}
            </p>
            {location['Danger / Hostility'] && (
              <p className="danger-note">{location['Danger / Hostility']}</p>
            )}
          </div>
          <div className="location-map-actions">
            {showBackToSubMap && (
              <button
                type="button"
                className="btn secondary glass-btn location-submap-back"
                onClick={onOpenParentSubMap}
              >
                Back to {parentSubMapName}
              </button>
            )}
            <div className="location-map-action-stack">
              <button
                type="button"
                className="map-icon-btn"
                onClick={onOpenMap}
                aria-label="Open world map"
                title="Open world map"
              >
                <MapIcon />
              </button>
              {signedIn && (
                <button
                  type="button"
                  className="map-icon-btn nearby-players-btn"
                  onClick={() => setNearbyOpen(true)}
                  aria-label="Nearby adventurers"
                  title="Nearby adventurers"
                >
                  <NearbyPlayersIcon />
                </button>
              )}
            </div>
          </div>
        </header>

        {showSubMapEntrance && (
          <div className="location-overlay-actions">
            <button type="button" className="btn secondary glass-btn" onClick={onOpenSubMap}>
              {gatewayLabel}
            </button>
          </div>
        )}

        {rewardSummary}

        {activityError && (
          <section className="panel panel-error glass-panel">
            <p className="lead">{activityError}</p>
          </section>
        )}

        <div className="location-dock">
          {hasStatusPanel ? <div className="location-stage">{statusPanel}</div> : null}

          <div className="location-bottom-band">
            <div className="location-bottom-panels">
            {showActivityPanel && (
              <section className="panel glass-panel location-activities">
                <h2>Activities</h2>
                <ul className="interaction-list">
                  {activities.map((activity) => {
                    const active = currentActivityId === activity['Activity ID']
                    const label = activity['Contextual Name'] ?? activity['Internal Key']
                    const hint = requirementHint?.(activity) ?? null
                    const recipeBrowser = isRecipeBrowserActivity?.(activity) ?? false
                    const startLabel = recipeBrowser
                      ? 'Recipes'
                      : currentActivityId
                        ? 'Replace'
                        : 'Start'
                    return (
                      <li key={activity['Activity ID']}>
                        <div>
                          <strong>{label}</strong>
                          {activity['Danger Warning Combat Level'] != null && (
                            <p className="danger-note">
                              Combat warning ~ Level {activity['Danger Warning Combat Level']}
                            </p>
                          )}
                          {activity.Description && <p className="muted">{activity.Description}</p>}
                          {hint && !active && <p className="muted tiny">{hint}</p>}
                        </div>
                        {active ? (
                          <button
                            type="button"
                            className="btn secondary"
                            disabled={actionsLocked}
                            onClick={onStopActivity}
                          >
                            Stop
                          </button>
                        ) : (
                          <button
                            type="button"
                            className="btn primary"
                            disabled={actionsLocked && !recipeBrowser}
                            onClick={() => {
                              onStartActivity(activity['Activity ID'])
                              scrollLocationToTop()
                            }}
                          >
                            {startLabel}
                          </button>
                        )}
                      </li>
                    )
                  })}
                  {specialStations.map((station) => (
                    <li key={`${station.facility['Facility ID']}-${station.skillId}`}>
                      <div>
                        <strong>{station.label}</strong>
                      </div>
                      <button
                        type="button"
                        className="btn primary"
                        onClick={() => {
                          onOpenSpecialProduction(station)
                          scrollLocationToTop()
                        }}
                      >
                        Open
                      </button>
                    </li>
                  ))}
                </ul>
              </section>
            )}

            {shops.length > 0 && (
              <section className="panel glass-panel location-activities">
                <h2>Shops</h2>
                <ul className="interaction-list">
                  {shops.map((shop) => (
                    <li key={shop['Shop ID']}>
                      <div>
                        <strong>{shop['Display Name']}</strong>
                      </div>
                      <button
                        type="button"
                        className="btn secondary"
                        onClick={() => {
                          onOpenShop(shop['Shop ID'])
                          scrollLocationToTop()
                        }}
                      >
                        Shop
                      </button>
                    </li>
                  ))}
                </ul>
              </section>
            )}

            {npcs.length > 0 && (
              <section className="panel glass-panel location-activities">
                <h2>People</h2>
                <ul className="interaction-list">
                  {npcs.map((npc) => {
                    const isMerchant = (npc.Role ?? '').toLowerCase() === 'merchant'
                    return (
                      <li key={npc['NPC ID']}>
                        <div>
                          <strong>{npc['Display Name']}</strong>
                          {!isMerchant && npc.Description && (
                            <p className="muted">{npc.Description}</p>
                          )}
                        </div>
                        <button
                          type="button"
                          className="btn secondary"
                          onClick={() => {
                            onOpenNpc(npc['NPC ID'])
                            scrollLocationToTop()
                          }}
                        >
                          {isMerchant ? 'Talk to merchant' : 'Talk'}
                        </button>
                      </li>
                    )
                  })}
                </ul>
              </section>
            )}

            {searchSpots.length > 0 && (
              <section className="panel glass-panel location-activities">
                <h2>Search</h2>
                <ul className="interaction-list">
                  {searchSpots.map((search) => {
                    const remainingMs = locationSearchCooldownRemainingMs(save, search, nowTick)
                    const ready = canClaimLocationSearch(save, search, nowTick)
                    return (
                      <li key={search['Search ID']}>
                        <div>
                          <strong>{search['Display Name']}</strong>
                          {!ready && (
                            <p className="muted tiny">
                              Come back in {formatDurationSeconds(remainingMs / 1000)}.
                            </p>
                          )}
                        </div>
                        <button
                          type="button"
                          className="btn primary"
                          disabled={!ready}
                          onClick={() => onSearchLocation(search['Search ID'])}
                        >
                          {search['Button Label']}
                        </button>
                      </li>
                    )
                  })}
                </ul>
              </section>
            )}
            </div>
          </div>
        </div>
      </div>
    </section>
    <ActivePlayersPanel
      save={save}
      skillNameForId={resolveSkillName}
      open={nearbyOpen}
      onClose={() => setNearbyOpen(false)}
    />
    </>
  )
}
