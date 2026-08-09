import { locationAssetPath } from '../game/assets/assetMap'
import type { ActivityRow, DatabaseIndexes, LocationRow } from '../game/data/types'
import { CASTLE_GATEWAY_ID, CAVE_ENTRANCE_ID } from '../game/world/constants'

interface LocationViewProps {
  indexes: DatabaseIndexes
  location: LocationRow
  currentActivityId: string | null
  activityError: string | null
  actionsLocked?: boolean
  onStartActivity: (activityId: string) => void
  onStopActivity: () => void
  onOpenMap: () => void
  onOpenSubMap?: () => void
  requirementHint?: (activity: ActivityRow) => string | null
}

export function LocationView({
  indexes,
  location,
  currentActivityId,
  activityError,
  actionsLocked = false,
  onStartActivity,
  onStopActivity,
  onOpenMap,
  onOpenSubMap,
  requirementHint,
}: LocationViewProps) {
  const locationId = location['Location ID']
  const activities = indexes.activitiesByLocationId.get(locationId) ?? []

  return (
    <section className="location-view">
      <div
        className="location-hero"
        style={{ backgroundImage: `url(${locationAssetPath(locationId)})` }}
      >
        <div className="location-hero-shade">
          <h1>{location['Display Name']}</h1>
          {location['Danger / Hostility'] && (
            <p className="danger-note">{location['Danger / Hostility']}</p>
          )}
        </div>
      </div>

      <div className="panel">
        <p className="lead">{location.Description ?? 'Explore this place.'}</p>
        <div className="button-row">
          <button type="button" className="btn secondary" onClick={onOpenMap}>
            Open Map
          </button>
          {onOpenSubMap && (locationId === CAVE_ENTRANCE_ID || locationId === CASTLE_GATEWAY_ID) && (
            <button type="button" className="btn secondary" onClick={onOpenSubMap}>
              {locationId === CAVE_ENTRANCE_ID ? 'Enter Caves' : 'Enter Castle'}
            </button>
          )}
        </div>
      </div>

      {activityError && (
        <section className="panel panel-error">
          <p className="lead">{activityError}</p>
        </section>
      )}

      <section className="panel">
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
    </section>
  )
}
