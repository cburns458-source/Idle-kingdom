import { enemyAssetPath } from '../game/assets/enemyAssets'
import type { EnemyRow } from '../game/data/enemyTypes'

interface CombatPanelProps {
  enemy: EnemyRow
  enemyHp: number
  playerHp: number
  playerMaxHp: number
  /** Damage the player dealt last round (orange overlay on enemy). */
  lastPlayerHit: number | null
  /** Damage the enemy dealt last round (centered above player). */
  lastEnemyHit: number | null
  /** When set, show "defeated" in place of the enemy art. */
  defeatedFlash: boolean
  deathPauseRemainingMs: number
}

export function CombatPanel({
  enemy,
  enemyHp,
  playerHp,
  playerMaxHp,
  lastPlayerHit,
  lastEnemyHit,
  defeatedFlash,
  deathPauseRemainingMs,
}: CombatPanelProps) {
  const enemyMax = Math.max(1, enemy['Maximum HP'])
  const pauseSec = Math.ceil(deathPauseRemainingMs / 1000)

  return (
    <section className="panel combat-panel" aria-label="Combat">
      <div className="combat-layout">
        <div className="combat-side combat-player-side">
          <div className="combat-float-slot">
            {lastEnemyHit != null && lastEnemyHit > 0 && !defeatedFlash && (
              <span className="combat-damage combat-damage-enemy">{lastEnemyHit}</span>
            )}
          </div>
          <div className="combat-portrait combat-portrait-player" aria-hidden>
            {deathPauseRemainingMs > 0 && (
              <span className="combat-recovering">Recovering… {pauseSec}s</span>
            )}
          </div>
          <div className="combat-meta combat-meta-player">
            <p className="combat-enemy-name combat-player-spacer" aria-hidden>
              &nbsp;
            </p>
            <p className="combat-hp combat-hp-player">
              {playerHp}/{playerMaxHp}
            </p>
          </div>
        </div>

        <div className="combat-side combat-enemy-side">
          <div className="combat-portrait combat-portrait-enemy">
            {defeatedFlash ? (
              <span className="combat-defeated">defeated</span>
            ) : (
              <>
                <div
                  className="combat-enemy-art"
                  style={{ backgroundImage: `url(${enemyAssetPath(enemy['Enemy ID'])})` }}
                  role="img"
                  aria-label={enemy['Display Name']}
                />
                {lastPlayerHit != null && lastPlayerHit > 0 && (
                  <span className="combat-damage combat-damage-player">{lastPlayerHit}</span>
                )}
              </>
            )}
          </div>
          <div className="combat-meta combat-meta-enemy">
            <p className="combat-enemy-name">{enemy['Display Name']}</p>
            <p className="combat-hp combat-hp-enemy">
              {defeatedFlash ? 0 : enemyHp}/{enemyMax}
            </p>
          </div>
        </div>
      </div>
    </section>
  )
}
