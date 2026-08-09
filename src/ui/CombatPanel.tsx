import { enemyAssetPath } from '../game/assets/enemyAssets'
import type { EnemyRow } from '../game/data/enemyTypes'
import type { ActivityRow, ItemRow } from '../game/data/types'
import type { ActionRewardBundle } from '../game/activity/types'
import { ActionRewardList } from './ActionRewardList'
import { formatDurationSeconds } from './formatDuration'

interface CombatPanelProps {
  activity: ActivityRow
  enemy: EnemyRow
  enemyHp: number
  playerHp: number
  playerMaxHp: number
  roundProgress: number
  /** Combat round length in ms (from config). */
  roundDurationMs: number
  deathPauseRemainingMs: number
  lastCombatMessage: string | null
  recentRewards: ActionRewardBundle[]
  itemsById?: Map<string, ItemRow>
  onStop: () => void
}

export function CombatPanel({
  activity,
  enemy,
  enemyHp,
  playerHp,
  playerMaxHp,
  roundProgress,
  roundDurationMs,
  deathPauseRemainingMs,
  lastCombatMessage,
  recentRewards,
  itemsById,
  onStop,
}: CombatPanelProps) {
  const enemyPct = Math.round((enemyHp / Math.max(1, enemy['Maximum HP'])) * 100)
  const playerPct = Math.round((playerHp / Math.max(1, playerMaxHp)) * 100)
  const clampedRound = Math.min(1, Math.max(0, roundProgress))
  const roundPct = Math.round(clampedRound * 100)
  const pauseSec = Math.ceil(deathPauseRemainingMs / 1000)
  const label = activity['Contextual Name'] ?? activity['Internal Key']
  const roundSeconds = Math.max(0, roundDurationMs / 1000)
  const roundElapsedSeconds = Math.min(roundSeconds, clampedRound * roundSeconds)

  return (
    <section className="panel combat-panel">
      <div className="activity-panel-head">
        <div>
          <h2>{label}</h2>
          <p className="muted">Combat</p>
        </div>
        {deathPauseRemainingMs <= 0 && (
          <button type="button" className="btn secondary" onClick={onStop}>
            Stop
          </button>
        )}
      </div>

      <div
        className="combat-enemy-art"
        style={{ backgroundImage: `url(${enemyAssetPath(enemy['Enemy ID'])})` }}
        aria-hidden
      />

      <p className="lead">
        Fighting <strong>{enemy['Display Name']}</strong>
        {enemy['Combat Level'] != null ? ` · Lv ${enemy['Combat Level']}` : ''}
      </p>

      <div className="combat-bars">
        <div>
          <div className="combat-bar-label">
            <span>Enemy</span>
            <span>
              {enemyHp} / {enemy['Maximum HP']}
            </span>
          </div>
          <div className="action-bar">
            <div className="action-bar-fill combat-enemy-fill" style={{ width: `${enemyPct}%` }} />
          </div>
        </div>
        <div>
          <div className="combat-bar-label">
            <span>You</span>
            <span>
              {playerHp} / {playerMaxHp}
            </span>
          </div>
          <div className="action-bar">
            <div className="action-bar-fill combat-player-fill" style={{ width: `${playerPct}%` }} />
          </div>
        </div>
      </div>

      {deathPauseRemainingMs > 0 ? (
        <p className="danger-note">Recovering… {pauseSec}s</p>
      ) : (
        <>
          <p className="muted">Round</p>
          <div className="action-bar">
            <div className="action-bar-fill" style={{ width: `${roundPct}%` }} />
          </div>
          <p className="muted tiny">
            Time elapsed: {formatDurationSeconds(roundElapsedSeconds)} /{' '}
            {formatDurationSeconds(roundSeconds)}
          </p>
        </>
      )}

      <ActionRewardList rewards={recentRewards} itemsById={itemsById} />
      {lastCombatMessage && <p className="loot-message">{lastCombatMessage}</p>}
    </section>
  )
}
