import type { ReactNode } from 'react'
import { locationAssetPath } from '../game/assets/assetMap'
import type { ActivityRow, DatabaseIndexes, GameDatabase, LocationRow } from '../game/data/types'
import {
  specialProductionStationsAt,
  type SpecialProductionStation,
} from '../game/projects/projects'
import { CASTLE_GATEWAY_ID, CAVE_ENTRANCE_ID } from '../game/world/constants'

interface LocationViewProps {
  indexes: DatabaseIndexes
  db: GameDatabase
  location: LocationRow
  currentActivityId: string | null
  activityError: string | null
  actionsLocked?: boolean
  statusPanel?: ReactNode
  onStartActivity: (activityId: string) => void
  onStopActivity: () => void
  onOpenSpecialProduction: (station: SpecialProductionStation) => void
  onOpenShop: (shopId: string) => void
  onOpenNpc: (npcId: string) => void
  onOpenMap: () => void
  onOpenSubMap?: () => void
  requirementHint?: (activity: ActivityRow) => string | null
}

function MapIcon() {
  return (
    <span
      className="map-icon map-icon-pixel"
      style={{ backgroundImage: 'url(/assets/icons/ui/ui_map.png)' }}
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
  onStartActivity,
  onStopActivity,
  onOpenSpecialProduction,
  onOpenShop,
  onOpenNpc,
  onOpenMap,
  onOpenSubMap,
  requirementHint,
}: LocationViewProps) {
  const locationId = location['Location ID']
  const activities = indexes.activitiesByLocationId.get(locationId) ?? []
  const specialStations = specialProductionStationsAt(db, locationId)
  const shops = indexes.shopsByLocationId.get(locationId) ?? []
  const npcs = indexes.npcsByLocationId.get(locationId) ?? []
  const showSubMapEntrance =
    Boolean(onOpenSubMap) &&
    (locationId === CAVE_ENTRANCE_ID || locationId === CASTLE_GATEWAY_ID)
  const showActivityPanel =
    !showSubMapEntrance && (activities.length > 0 || specialStations.length > 0)

  return (
    <section
      className="location-view"
      style={{ backgroundImage: `url(${locationAssetPath(locationId)})` }}
    >
      <div className="location-view-shade">
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
          <button
            type="button"
            className="map-icon-btn"
            onClick={onOpenMap}
            aria-label="Open world map"
            title="Open world map"
          >
            <MapIcon />
          </button>
        </header>

        {showSubMapEntrance && (
          <div className="location-overlay-actions">
            <button type="button" className="btn secondary glass-btn" onClick={onOpenSubMap}>
              {locationId === CAVE_ENTRANCE_ID ? 'Enter Caves' : 'Enter Castle'}
            </button>
          </div>
        )}

        {statusPanel}

        {activityError && (
          <section className="panel panel-error glass-panel">
            <p className="lead">{activityError}</p>
          </section>
        )}

        {showActivityPanel && (
          <section className="panel glass-panel location-activities">
            <h2>Activities</h2>
            <ul className="interaction-list">
              {activities.map((activity) => {
                const active = currentActivityId === activity['Activity ID']
                const label = activity['Contextual Name'] ?? activity['Internal Key']
                const hint = requirementHint?.(activity) ?? null
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
                        disabled={actionsLocked}
                        onClick={() => onStartActivity(activity['Activity ID'])}
                      >
                        {currentActivityId ? 'Replace' : 'Start'}
                      </button>
                    )}
                  </li>
                )
              })}
              {specialStations.map((station) => (
                <li key={`${station.facility['Facility ID']}-${station.skillId}`}>
                  <div>
                    <strong>{station.label}</strong>
                    <p className="muted">{station.facility['Display Name']}</p>
                    <p className="muted tiny">Instant Special Production</p>
                  </div>
                  <button
                    type="button"
                    className="btn primary"
                    disabled={actionsLocked}
                    onClick={() => onOpenSpecialProduction(station)}
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
                    <p className="muted tiny">Passive shop</p>
                  </div>
                  <button
                    type="button"
                    className="btn primary"
                    onClick={() => onOpenShop(shop['Shop ID'])}
                  >
                    Trade
                  </button>
                </li>
              ))}
              {npcs.map((npc) => (
                <li key={npc['NPC ID']}>
                  <div>
                    <strong>{npc['Display Name']}</strong>
                    {npc.Role && <p className="muted tiny">{npc.Role}</p>}
                    {npc.Description && <p className="muted">{npc.Description}</p>}
                  </div>
                  <button
                    type="button"
                    className="btn primary"
                    onClick={() => onOpenNpc(npc['NPC ID'])}
                  >
                    Talk
                  </button>
                </li>
              ))}
            </ul>
          </section>
        )}
      </div>
    </section>
  )
}
