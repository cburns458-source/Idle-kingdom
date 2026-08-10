import { formatDurationSeconds } from './formatDuration'

const PLAYER_AVATAR_SRC = '/assets/player/player_adventurer_temp.png'
const GOLD_ICON_SRC = '/assets/icons/items/item_gold.png'

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
  gold: number
  currentHp: number
  maxHp: number
  /** When true, HP reads "Dead" instead of current/max (death pause). */
  dead?: boolean
  activityStatus: HudActivityStatus
}

export function TopHud({
  characterName,
  totalLevel,
  gold,
  currentHp,
  maxHp,
  dead = false,
  activityStatus,
}: TopHudProps) {
  const hpRatio =
    dead || maxHp <= 0 ? 0 : Math.max(0, Math.min(1, currentHp / maxHp))
  const hpLabel = dead
    ? 'Dead'
    : `${currentHp.toLocaleString()}/${maxHp.toLocaleString()}`

  return (
    <header className="top-hud">
      <div className="top-hud-main">
        <div className="top-hud-left">
          <div className="hud-avatar" aria-hidden="true">
            <img src={PLAYER_AVATAR_SRC} alt="" className="hud-avatar-image" />
          </div>
          <div className="top-hud-identity">
            <p className="brand">{characterName?.trim() || 'Adventurer'}</p>
            <p className="hud-total-level">Total level: {totalLevel.toLocaleString()}</p>
            <p className="hud-gold">
              <img src={GOLD_ICON_SRC} alt="" className="hud-gold-icon" />
              <span>{gold.toLocaleString()}</span>
            </p>
          </div>
        </div>

        <div className="top-hud-right">
          {activityStatus && (
            <div className="hud-activity" aria-live="polite">
              {activityStatus.kind === 'action' ? (
                <>
                  <p className="hud-activity-line">{activityStatus.activityName}</p>
                  <p className="hud-activity-line hud-activity-action">
                    {activityStatus.actionName}
                  </p>
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
          <p className={dead ? 'hud-hp-text dead' : 'hud-hp-text'}>{hpLabel}</p>
        </div>
      </div>

      <div className="top-hud-hp-row">
        <div
          className="hud-hp-bar"
          role="progressbar"
          aria-label="Hit points"
          aria-valuemin={0}
          aria-valuemax={maxHp}
          aria-valuenow={dead ? 0 : currentHp}
          aria-valuetext={hpLabel}
        >
          <div className="hud-hp-bar-fill" style={{ transform: `scaleX(${hpRatio})` }} />
        </div>
      </div>
    </header>
  )
}
