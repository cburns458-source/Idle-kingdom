import { formatDurationSeconds } from './formatDuration'

const PLAYER_AVATAR_SRC = '/assets/player/player_adventurer_temp.png'
const AVATAR_FRAME_SRC = '/assets/player/avatar_frame_pixel.png'
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
  raceName?: string | null
  totalLevel: number
  totalXp: number
  /** When true, show total XP instead of total level. */
  showTotalXp?: boolean
  onToggleTotalStat?: () => void
  gold: number
  currentHp: number
  maxHp: number
  /** When true, HP reads "Dead" instead of current/max (death pause). */
  dead?: boolean
  activityStatus: HudActivityStatus
  onOpenWardrobe: () => void
  /** Pulses the avatar button until the player opens the Wardrobe for the first time. */
  wardrobeHint?: boolean
}

export function TopHud({
  characterName,
  raceName = null,
  totalLevel,
  totalXp,
  showTotalXp = false,
  onToggleTotalStat,
  gold,
  currentHp,
  maxHp,
  dead = false,
  activityStatus,
  onOpenWardrobe,
  wardrobeHint = false,
}: TopHudProps) {
  const hpRatio =
    dead || maxHp <= 0 ? 0 : Math.max(0, Math.min(1, currentHp / maxHp))
  const hpLabel = dead
    ? 'Dead'
    : `${currentHp.toLocaleString()}/${maxHp.toLocaleString()}`
  const totalStatLabel = showTotalXp
    ? `Total XP: ${totalXp.toLocaleString()}`
    : `Total level: ${totalLevel.toLocaleString()}`

  return (
    <header className="top-hud">
      <button
        type="button"
        className={`hud-avatar${wardrobeHint ? ' hud-avatar-hint' : ''}`}
        onClick={onOpenWardrobe}
        aria-label="Open wardrobe"
        title="Wardrobe"
      >
        <span className="hud-avatar-portrait">
          <img src={PLAYER_AVATAR_SRC} alt="" className="hud-avatar-image" />
        </span>
        <img src={AVATAR_FRAME_SRC} alt="" className="hud-avatar-frame" />
      </button>

      <div className="top-hud-main">
        <div className="top-hud-identity">
          <p className="brand">{characterName?.trim() || 'Adventurer'}</p>
          {raceName && <p className="hud-race muted tiny">{raceName}</p>}
          {onToggleTotalStat ? (
            <button
              type="button"
              className="hud-total-stat"
              onClick={onToggleTotalStat}
              aria-label={
                showTotalXp
                  ? 'Show total level. Currently showing total XP.'
                  : 'Show total XP. Currently showing total level.'
              }
            >
              {totalStatLabel}
            </button>
          ) : (
            <p className="hud-total-stat">{totalStatLabel}</p>
          )}
          <p className="hud-gold">
            <img src={GOLD_ICON_SRC} alt="" className="hud-gold-icon" />
            <span>{gold.toLocaleString()}</span>
          </p>
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
        </div>
      </div>

      <div className="top-hud-hp-row">
        <div className="top-hud-hp-cluster">
          <p className={dead ? 'hud-hp-text dead' : 'hud-hp-text'}>{hpLabel}</p>
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
      </div>
    </header>
  )
}
