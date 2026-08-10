import { useEffect, useRef, useState, type ReactNode } from 'react'
import { locationAssetPath, uiMapAssetPath } from '../game/assets/assetMap'
import type { ActivityRow, DatabaseIndexes, GameDatabase, LocationRow } from '../game/data/types'
import {
  specialProductionStationsAt,
  type SpecialProductionStation,
} from '../game/projects/projects'
import { enterSubMapLabel, isSubMapGateway } from '../game/world/submaps'

interface LocationViewProps {
  indexes: DatabaseIndexes
  db: GameDatabase
  location: LocationRow
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
  requirementHint?: (activity: ActivityRow) => string | null
  /** Standard Production opens a recipe picker. */
  isRecipeBrowserActivity?: (activity: ActivityRow) => boolean
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

export function LocationView({
  indexes,
  db,
  location,
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
  requirementHint,
  isRecipeBrowserActivity,
}: LocationViewProps) {
  const locationId = location['Location ID']
  const activities = indexes.activitiesByLocationId.get(locationId) ?? []
  const specialStations = specialProductionStationsAt(db, locationId)
  const shops = indexes.shopsByLocationId.get(locationId) ?? []
  const npcs = indexes.npcsByLocationId.get(locationId) ?? []
  const gatewayLabel =
    enterSubMapLabelText ?? enterSubMapLabel(db, location)
  const showSubMapEntrance =
    Boolean(onOpenSubMap) && isSubMapGateway(location) && Boolean(gatewayLabel)
  const showBackToSubMap =
    Boolean(onOpenParentSubMap) && Boolean(parentSubMapName) && !showSubMapEntrance
  const showActivityPanel =
    !showSubMapEntrance && (activities.length > 0 || specialStations.length > 0)
  const [activitiesHidden, setActivitiesHidden] = useState(false)
  const shadeRef = useRef<HTMLDivElement | null>(null)

  useEffect(() => {
    setActivitiesHidden(false)
  }, [locationId])

  function scrollLocationToTop() {
    const shade = shadeRef.current
    if (!shade) return
    // Wait a frame so status panels (shop / NPC / activity) can mount first.
    requestAnimationFrame(() => {
      shade.scrollTo({ top: 0, behavior: 'smooth' })
    })
  }

  return (
    <section
      className="location-view"
      style={{ backgroundImage: `url(${locationAssetPath(locationId)})` }}
    >
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
            <button
              type="button"
              className="map-icon-btn"
              onClick={onOpenMap}
              aria-label="Open world map"
              title="Open world map"
            >
              <MapIcon />
            </button>
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

        <div className="location-stage">
          {statusPanel}

          <div className="location-bottom-panels">
          {showActivityPanel && activitiesHidden && (
            <div className="location-activities-reveal">
              <button
                type="button"
                className="btn secondary glass-btn"
                onClick={() => setActivitiesHidden(false)}
              >
                Show activities
              </button>
            </div>
          )}

          {showActivityPanel && !activitiesHidden && (
            <section className="panel glass-panel location-activities">
              <div className="location-activities-head">
                <h2>Activities</h2>
                <button
                  type="button"
                  className="btn secondary location-activities-hide"
                  onClick={() => setActivitiesHidden(true)}
                >
                  Hide
                </button>
              </div>
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

          {(shops.length > 0 || npcs.length > 0) && (
            <section className="panel glass-panel location-activities">
              <h2>People & shops</h2>
              <ul className="interaction-list">
                {shops.map((shop) => (
                  <li key={shop['Shop ID']}>
                    <div>
                      <strong>{shop['Display Name']}</strong>
                      {shop.Description && <p className="muted">{shop.Description}</p>}
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
          </div>
        </div>
      </div>
    </section>
  )
}
