import type { ReactNode } from 'react'
import { locationAssetPath } from '../game/assets/assetMap'
import type { ActivityRow, DatabaseIndexes, LocationRow } from '../game/data/types'
import { CASTLE_GATEWAY_ID, CAVE_ENTRANCE_ID } from '../game/world/constants'

interface LocationViewProps {
  indexes: DatabaseIndexes
  location: LocationRow
  currentActivityId: string | null
  activityError: string | null
  actionsLocked?: boolean
  statusPanel?: ReactNode
  onStartActivity: (activityId: string) => void
  onStopActivity: () => void
  onOpenMap: () => void
  onOpenSubMap?: () => void
  requirementHint?: (activity: ActivityRow) => string | null
}

function MapIcon() {
  return (
    <svg className="map-icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path
        fill="currentColor"
        d="M3.5 5.8 9 4.2l6 1.7 5.5-1.7v14l-5.5 1.7-6-1.7-5.5 1.7V5.8Zm2 .9v10.7l3.5-1.1V5.6L5.5 6.7Zm5.5-.9v10.8l4 1.1V7l-4-1.2Zm6 1.4v10.8l3.5-1.1V6.1L17 7.2Z"
      />
    </svg>
  )
}

export function LocationView({
  indexes,
  location,
  currentActivityId,
  activityError,
  actionsLocked = false,
  statusPanel,
  onStartActivity,
  onStopActivity,
  onOpenMap,
  onOpenSubMap,
  requirementHint,
}: LocationViewProps) {
  const locationId = location['Location ID']
  const activities = indexes.activitiesByLocationId.get(locationId) ?? []
  const showSubMap =
    Boolean(onOpenSubMap) &&
    (locationId === CAVE_ENTRANCE_ID || locationId === CASTLE_GATEWAY_ID)

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

        {showSubMap && (
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

        <section className="panel glass-panel location-activities">
          <h2>Activities</h2>
          {activities.length === 0 ? (
            <p className="muted">No activities at this location.</p>
          ) : (
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
            </ul>
          )}
        </section>
      </div>
    </section>
  )
}
