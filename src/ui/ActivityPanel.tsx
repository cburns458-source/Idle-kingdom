import type { ActionRow, ActivityRow, SkillRow } from '../game/data/types'
import { isBelowProficiency } from '../game/activity/gathering'
import type { PlayerSave } from '../game/save/types'
import type { LootGrant } from '../game/activity/types'

interface ActivityPanelProps {
  activity: ActivityRow
  action: ActionRow | null
  save: PlayerSave
  skill: SkillRow | undefined
  progress: number
  /** True action duration in ms (includes proficiency multiplier). */
  durationMs: number | null
  recentLoot: LootGrant[]
  lastMessage: string | null
  onStop: () => void
}

function formatSeconds(value: number): string {
  if (!Number.isFinite(value) || value < 0) return '0'
  const rounded = Math.round(value * 10) / 10
  return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(1)
}

export function ActivityPanel({
  activity,
  action,
  save,
  skill,
  progress,
  durationMs,
  recentLoot,
  lastMessage,
  onStop,
}: ActivityPanelProps) {
  const clamped = Math.min(1, Math.max(0, progress))
  const pct = Math.round(clamped * 100)
  const slow = action ? isBelowProficiency(save, action) : false
  const label = activity['Contextual Name'] ?? activity['Internal Key']
  const totalSeconds = Math.max(0, (durationMs ?? 0) / 1000)
  const elapsedSeconds = Math.min(totalSeconds, clamped * totalSeconds)

  return (
    <section className="panel activity-panel">
      <div className="activity-panel-head">
        <div>
          <h2>{label}</h2>
          <p className="muted">Primary Activity</p>
        </div>
        <button type="button" className="btn secondary" onClick={onStop}>
          Stop
        </button>
      </div>

      {action ? (
        <>
          <p className="lead">
            Current action: <strong>{action['Display Name']}</strong>
          </p>
          <p className="muted">{skill?.['Display Name'] ?? 'Skill'}</p>
          {slow && <p className="tough-work">this is tough work</p>}
          <div className="action-bar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={pct}>
            <div className="action-bar-fill" style={{ width: `${pct}%` }} />
          </div>
          <p className="muted tiny">
            {formatSeconds(elapsedSeconds)} / {formatSeconds(totalSeconds)}s
          </p>
        </>
      ) : (
        <p className="lead">Preparing next action…</p>
      )}

      {lastMessage && <p className="loot-message">{lastMessage}</p>}

      {recentLoot.length > 0 && (
        <ul className="plain-list">
          {recentLoot.slice(0, 5).map((loot, index) => (
            <li key={`${loot.itemId}-${index}`}>
              +{loot.quantity} {loot.displayName}
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}
