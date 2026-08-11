import { useEffect, useState } from 'react'
import { createPortal } from 'react-dom'
import { CloseButton } from './CloseButton'
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
}

export function TopHud({
  characterName,
  totalLevel,
  totalXp,
  showTotalXp = false,
  onToggleTotalStat,
  gold,
  currentHp,
  maxHp,
  dead = false,
  activityStatus,
}: TopHudProps) {
  const [wardrobeOpen, setWardrobeOpen] = useState(false)
  const hpRatio =
    dead || maxHp <= 0 ? 0 : Math.max(0, Math.min(1, currentHp / maxHp))
  const hpLabel = dead
    ? 'Dead'
    : `${currentHp.toLocaleString()}/${maxHp.toLocaleString()}`
  const totalStatLabel = showTotalXp
    ? `Total XP: ${totalXp.toLocaleString()}`
    : `Total level: ${totalLevel.toLocaleString()}`

  useEffect(() => {
    if (!wardrobeOpen) return
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') {
        event.preventDefault()
        setWardrobeOpen(false)
      }
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [wardrobeOpen])

  return (
    <>
      <header className="top-hud">
        <button
          type="button"
          className="hud-avatar"
          onClick={() => setWardrobeOpen(true)}
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

      {wardrobeOpen &&
        createPortal(
          <div
            className="quest-reward-overlay wardrobe-overlay"
            role="dialog"
            aria-modal="true"
            aria-labelledby="wardrobe-title"
            onClick={() => setWardrobeOpen(false)}
          >
            <div
              className="panel quest-reward-card wardrobe-card"
              onClick={(event) => event.stopPropagation()}
            >
              <div className="activity-panel-head">
                <h2 id="wardrobe-title">Wardrobe</h2>
                <CloseButton onClick={() => setWardrobeOpen(false)} />
              </div>
              <p className="lead">Wardrobe coming soon…</p>
            </div>
          </div>,
          document.body,
        )}
    </>
  )
}
