import { useEffect, useState } from 'react'
import { enemyAssetPath } from '../game/assets/enemyAssets'
import { playerCombatAssetPath } from '../game/assets/playerAssets'
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

function randomDamageOffset(): { x: number; y: number } {
  return {
    x: Math.round((Math.random() - 0.5) * 48),
    y: Math.round((Math.random() - 0.5) * 36),
  }
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
  const playerMax = Math.max(1, playerMaxHp)
  const enemyPct = Math.max(0, Math.min(100, (enemyHp / enemyMax) * 100))
  const playerPct = Math.max(0, Math.min(100, (playerHp / playerMax) * 100))
  const pauseSec = Math.ceil(deathPauseRemainingMs / 1000)

  const [playerHitOffset, setPlayerHitOffset] = useState({ x: 0, y: 0 })
  const [enemyHitOffset, setEnemyHitOffset] = useState({ x: 0, y: 0 })

  // Nudge popup position each time a hit lands (HP change covers same-damage rounds).
  useEffect(() => {
    if (lastPlayerHit != null && lastPlayerHit > 0) {
      setPlayerHitOffset(randomDamageOffset())
    }
  }, [lastPlayerHit, enemyHp])

  useEffect(() => {
    if (lastEnemyHit != null && lastEnemyHit > 0) {
      setEnemyHitOffset(randomDamageOffset())
    }
  }, [lastEnemyHit, playerHp])

  return (
    <section className="panel combat-panel" aria-label="Combat">
      <div className="combat-layout">
        <div className="combat-side combat-player-side">
          <div className="combat-float-slot">
            {lastEnemyHit != null && lastEnemyHit > 0 && !defeatedFlash && (
              <span
                className="combat-damage combat-damage-enemy"
                style={{
                  ['--damage-x' as string]: `${enemyHitOffset.x}px`,
                  ['--damage-y' as string]: `${enemyHitOffset.y}px`,
                }}
              >
                {lastEnemyHit}
              </span>
            )}
          </div>
          <div className="combat-portrait combat-portrait-player">
            <div
              className="combat-player-art"
              style={{ backgroundImage: `url(${playerCombatAssetPath()})` }}
              role="img"
              aria-label="Adventurer"
            />
            {deathPauseRemainingMs > 0 && (
              <span className="combat-recovering">Recovering… {pauseSec}s</span>
            )}
          </div>
          <div className="combat-meta combat-meta-player">
            <p className="combat-enemy-name combat-player-spacer" aria-hidden>
              &nbsp;
            </p>
            <div
              className="combat-hp-bar"
              role="meter"
              aria-label="Player health"
              aria-valuemin={0}
              aria-valuemax={playerMax}
              aria-valuenow={playerHp}
            >
              <div className="combat-hp-bar-fill combat-hp-bar-fill-player" style={{ width: `${playerPct}%` }} />
            </div>
          </div>
        </div>

        <div className="combat-side combat-enemy-side">
          <div className="combat-float-slot" aria-hidden />
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
                  <span
                    className="combat-damage combat-damage-player"
                    style={{
                      ['--damage-x' as string]: `${playerHitOffset.x}px`,
                      ['--damage-y' as string]: `${playerHitOffset.y}px`,
                    }}
                  >
                    {lastPlayerHit}
                  </span>
                )}
              </>
            )}
          </div>
          <div className="combat-meta combat-meta-enemy">
            <p className="combat-enemy-name">{enemy['Display Name']}</p>
            <div
              className="combat-hp-bar"
              role="meter"
              aria-label={`${enemy['Display Name']} health`}
              aria-valuemin={0}
              aria-valuemax={enemyMax}
              aria-valuenow={defeatedFlash ? 0 : enemyHp}
            >
              <div
                className="combat-hp-bar-fill combat-hp-bar-fill-enemy"
                style={{ width: `${defeatedFlash ? 0 : enemyPct}%` }}
              />
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
