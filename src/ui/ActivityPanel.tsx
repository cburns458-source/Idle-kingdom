import { actionAssetPath } from '../game/assets/actionAssets'
import { playerCombatAssetPath } from '../game/assets/playerAssets'
import type { ActionRow, ActivityRow, SkillRow } from '../game/data/types'
import { isBelowProficiency } from '../game/activity/gathering'
import type { PlayerSave } from '../game/save/types'
import { formatDurationSeconds } from './formatDuration'

interface ActivityPanelProps {
  activity: ActivityRow
  action: ActionRow | null
  save: PlayerSave
  skill: SkillRow | undefined
  progress: number
  /** True action duration in ms (includes proficiency multiplier). */
  durationMs: number | null
}

export function ActivityPanel({
  action,
  save,
  progress,
  durationMs,
}: ActivityPanelProps) {
  const clamped = Math.min(1, Math.max(0, progress))
  const pct = Math.round(clamped * 100)
  const slow = action ? isBelowProficiency(save, action) : false
  const actionName = action?.['Display Name'] ?? 'Preparing…'
  const actionId = action?.['Action ID']
  const totalSeconds = Math.max(0, (durationMs ?? 0) / 1000)
  const elapsedSeconds = Math.min(totalSeconds, clamped * totalSeconds)

  return (
    <section className="panel activity-panel gather-panel" aria-label="Gathering">
      <div className="combat-layout gather-layout">
        <div className="combat-side combat-player-side">
          <div className="combat-portrait combat-portrait-player">
            <div
              className="combat-player-art"
              style={{ backgroundImage: `url(${playerCombatAssetPath()})` }}
              role="img"
              aria-label="Adventurer"
            />
          </div>
          <div className="combat-meta combat-meta-player">
            <p className="combat-enemy-name combat-player-spacer" aria-hidden>
              &nbsp;
            </p>
          </div>
        </div>

        <div className="combat-side combat-enemy-side">
          <div className="combat-portrait combat-portrait-enemy">
            {actionId ? (
              <div
                className="combat-enemy-art gather-action-art"
                style={{ backgroundImage: `url(${actionAssetPath(actionId)})` }}
                role="img"
                aria-label={actionName}
              />
            ) : (
              <span className="gather-preparing">…</span>
            )}
          </div>
          <div className="combat-meta combat-meta-enemy">
            <p className="combat-enemy-name">{actionName}</p>
            {slow && <p className="tough-work gather-tough">this is tough work</p>}
          </div>
        </div>
      </div>

      <div className="gather-progress-row">
        <div
          className="combat-round-bar gather-progress-bar"
          role="progressbar"
          aria-label="Action progress"
          aria-valuemin={0}
          aria-valuemax={100}
          aria-valuenow={pct}
        >
          <div
            className="combat-round-bar-fill gather-progress-fill"
            style={{ transform: `scaleX(${clamped})` }}
          />
        </div>
        <p className="gather-progress-time muted tiny">
          {formatDurationSeconds(elapsedSeconds)} / {formatDurationSeconds(totalSeconds)}
        </p>
      </div>
    </section>
  )
}
