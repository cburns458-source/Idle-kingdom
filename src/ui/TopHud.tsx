import { formatDurationSeconds } from './formatDuration'

export type HudActivityStatus =
  | {
      kind: 'action'
      activityName: string
      actionName: string
      elapsedSeconds: number
    }
  | {
      kind: 'production'
      itemName: string
      completed: number
      total: number
      remainingSeconds: number
    }
  | null

interface TopHudProps {
  characterName: string | null
  totalLevel: number
  totalXp: number
  gold: number
  currentHp: number
  maxHp: number
  /** When true, HP reads "Dead" instead of current/max (death pause). */
  dead?: boolean
  locationLabel: string
  activityStatus: HudActivityStatus
}

export function TopHud({
  characterName,
  totalLevel,
  totalXp,
  gold,
  currentHp,
  maxHp,
  dead = false,
  locationLabel,
  activityStatus,
}: TopHudProps) {
  return (
    <header className="top-hud">
      <div className="top-hud-row">
        <div className="top-hud-brand">
          <p className="brand">{characterName?.trim() || 'Adventurer'}</p>
          <p className="hud-location">{locationLabel}</p>
        </div>
        {activityStatus && (
          <div className="hud-activity" aria-live="polite">
            {activityStatus.kind === 'action' ? (
              <>
                <p className="hud-activity-line">{activityStatus.activityName}</p>
                <p className="hud-activity-line hud-activity-action">{activityStatus.actionName}</p>
                <p className="hud-activity-timer">
                  {formatDurationSeconds(activityStatus.elapsedSeconds)}
                </p>
              </>
            ) : (
              <>
                <p className="hud-activity-line">{activityStatus.itemName}</p>
                <p className="hud-activity-line">
                  {activityStatus.completed}/{activityStatus.total}
                </p>
                <p className="hud-activity-timer">
                  {formatDurationSeconds(activityStatus.remainingSeconds)}
                </p>
              </>
            )}
          </div>
        )}
      </div>
      <dl className="hud-stats">
        <div>
          <dt>Lvl</dt>
          <dd>{totalLevel.toLocaleString()}</dd>
        </div>
        <div>
          <dt>XP</dt>
          <dd>{totalXp.toLocaleString()}</dd>
        </div>
        <div>
          <dt>Gold</dt>
          <dd>{gold.toLocaleString()}</dd>
        </div>
        <div>
          <dt>HP</dt>
          <dd>{dead ? 'Dead' : `${currentHp.toLocaleString()}/${maxHp.toLocaleString()}`}</dd>
        </div>
      </dl>
    </header>
  )
}
