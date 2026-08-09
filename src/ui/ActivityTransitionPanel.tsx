import type { ActivityRow } from '../game/data/types'
import type { ActivityTransition } from '../game/save/types'

interface ActivityTransitionPanelProps {
  transition: ActivityTransition
  activity: ActivityRow | undefined
  followUpActivity?: ActivityRow | undefined
  remainingMs: number
  /** When false, the Cancel control is hidden (hard stop / delay finished). */
  showCancel?: boolean
  onCancel: () => void
}

export function ActivityTransitionPanel({
  transition,
  activity,
  followUpActivity,
  remainingMs,
  showCancel = true,
  onCancel,
}: ActivityTransitionPanelProps) {
  const total = Math.max(1, transition.durationMs)
  const elapsed = Math.min(total, total - remainingMs)
  const progress = Math.min(1, Math.max(0, elapsed / total))
  const pct = Math.round(progress * 100)
  const secondsLeft = Math.max(0, Math.ceil(remainingMs / 1000))
  const label = activity?.['Contextual Name'] ?? activity?.['Internal Key'] ?? 'Activity'
  const followUpLabel =
    followUpActivity?.['Contextual Name'] ??
    followUpActivity?.['Internal Key'] ??
    null
  const switching = transition.kind === 'stopping' && Boolean(transition.followUpActivityId)
  const title = switching ? 'Changing activity' : 'Stopping activity'
  const canCancel = showCancel && remainingMs > 0

  return (
    <section className="panel glass-panel activity-transition-panel" aria-live="polite">
      <div className="activity-panel-head">
        <div>
          <h2>{title}</h2>
          <p className="lead">{label}</p>
          {switching && followUpLabel ? (
            <p className="muted tiny">
              Next: <strong>{followUpLabel}</strong> — starts when this delay ends.
            </p>
          ) : (
            <p className="muted tiny">
              You can queue another activity here before the delay ends.
            </p>
          )}
        </div>
        {canCancel ? (
          <button type="button" className="btn secondary" onClick={onCancel}>
            Cancel
          </button>
        ) : null}
      </div>
      <div className="action-bar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={pct}>
        <div className="action-bar-fill" style={{ width: `${pct}%` }} />
      </div>
      <p className="muted tiny">{secondsLeft}s remaining</p>
    </section>
  )
}
