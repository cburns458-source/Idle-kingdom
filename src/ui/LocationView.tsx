import type { ReactNode } from 'react'
import { locationAssetPath } from '../game/assets/assetMap'
import type { ActivityRow, DatabaseIndexes, LocationRow } from '../game/data/types'

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
  location,
  currentActivityId,
  activityError,
  actionsLocked = false,
  statusPanel,
  onStartActivity,
  onStopActivity,
  onOpenMap,
  requirementHint,
}: LocationViewProps) {
  const locationId = location['Location ID']
  const activities = indexes.activitiesByLocationId.get(locationId) ?? []

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
