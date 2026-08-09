import type { ActivityRow } from '../game/data/types'
import type { ActivityTransition } from '../game/save/types'

interface ActivityTransitionPanelProps {
  transition: ActivityTransition
  activity: ActivityRow | undefined
  remainingMs: number
  onCancel: () => void
}

export function ActivityTransitionPanel({
  transition,
  activity,
  remainingMs,
  onCancel,
}: ActivityTransitionPanelProps) {
  const total = Math.max(1, transition.durationMs)
  const elapsed = Math.min(total, total - remainingMs)
  const progress = Math.min(1, Math.max(0, elapsed / total))
  const pct = Math.round(progress * 100)
  const secondsLeft = Math.max(0, Math.ceil(remainingMs / 1000))
  const label = activity?.['Contextual Name'] ?? activity?.['Internal Key'] ?? 'Activity'
  const switching = transition.kind === 'stopping' && Boolean(transition.followUpActivityId)
  const title =
    transition.kind === 'starting'
      ? 'Starting activity'
      : switching
        ? 'Cancelling activity'
        : 'Stopping activity'

  return (
    <section className="panel glass-panel activity-transition-panel" aria-live="polite">
      <div className="activity-panel-head">
        <div>
          <h2>{title}</h2>
          <p className="lead">{label}</p>
          {switching && (
            <p className="muted tiny">Then starting the selected activity after this delay.</p>
          )}
        </div>
        <button type="button" className="btn secondary" onClick={onCancel}>
          Cancel
        </button>
      </div>
      <div className="action-bar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={pct}>
        <div className="action-bar-fill" style={{ width: `${pct}%` }} />
      </div>
      <p className="muted tiny">{secondsLeft}s remaining</p>
    </section>
  )
}
