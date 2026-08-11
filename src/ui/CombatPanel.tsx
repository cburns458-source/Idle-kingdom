import { useEffect, useState } from 'react'
import { enemyAssetPath } from '../game/assets/enemyAssets'
import { playerCombatAssetPath } from '../game/assets/playerAssets'
import type { EnemyRow } from '../game/data/enemyTypes'

interface CombatPanelProps {
  enemy: EnemyRow
  enemyHp: number
  playerHp: number
  playerMaxHp: number
  /** ISO timestamp when the current combat round started. */
  roundStartedAt: string | null
  /** Combat round length in ms. */
  roundDurationMs: number
  /** Damage the player dealt last round (orange overlay on enemy). */
  lastPlayerHit: number | null
  /** Whether the last player hit was a critical strike. */
  lastPlayerCrit?: boolean
  /** Off-hand dagger damage last round (separate floater). */
  lastOffhandHit?: number | null
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
  roundStartedAt,
  roundDurationMs,
  lastPlayerHit,
  lastPlayerCrit = false,
  lastOffhandHit = null,
  lastEnemyHit,
  defeatedFlash,
  deathPauseRemainingMs,
}: CombatPanelProps) {
  const enemyMax = Math.max(1, enemy['Maximum HP'])
  const playerMax = Math.max(1, playerMaxHp)
  const enemyPct = Math.max(0, Math.min(100, (enemyHp / enemyMax) * 100))
  const playerPct = Math.max(0, Math.min(100, (playerHp / playerMax) * 100))
  const pauseSec = Math.ceil(deathPauseRemainingMs / 1000)
  const showRoundBar = deathPauseRemainingMs <= 0 && !defeatedFlash && Boolean(roundStartedAt)

  const [roundProgress, setRoundProgress] = useState(0)
  const [playerHitOffset, setPlayerHitOffset] = useState({ x: 0, y: 0 })
  const [offhandHitOffset, setOffhandHitOffset] = useState({ x: 0, y: 0 })
  const [enemyHitOffset, setEnemyHitOffset] = useState({ x: 0, y: 0 })
  const [shownPlayerHit, setShownPlayerHit] = useState<number | null>(null)
  const [shownPlayerCrit, setShownPlayerCrit] = useState(false)
  const [shownOffhandHit, setShownOffhandHit] = useState<number | null>(null)
  const [shownEnemyHit, setShownEnemyHit] = useState<number | null>(null)

  // Smooth local round fill: 0 → 1 over roundDurationMs, resets each round.
  useEffect(() => {
    if (!showRoundBar || !roundStartedAt || roundDurationMs <= 0) {
      setRoundProgress(0)
      return
    }
    const started = Date.parse(roundStartedAt)
    if (!Number.isFinite(started)) {
      setRoundProgress(0)
      return
    }

    let frame = 0
    const tick = () => {
      const progress = Math.min(1, Math.max(0, (Date.now() - started) / roundDurationMs))
      setRoundProgress(progress)
      if (progress < 1) {
        frame = window.requestAnimationFrame(tick)
      }
    }
    frame = window.requestAnimationFrame(tick)
    return () => window.cancelAnimationFrame(frame)
  }, [showRoundBar, roundStartedAt, roundDurationMs])

  // Show hit pops briefly, nudge position each time, then clear after 2s.
  useEffect(() => {
    if (lastPlayerHit == null || lastPlayerHit <= 0) return
    setShownPlayerHit(lastPlayerHit)
    setShownPlayerCrit(lastPlayerCrit)
    setPlayerHitOffset(randomDamageOffset())
    const timer = window.setTimeout(() => {
      setShownPlayerHit(null)
      setShownPlayerCrit(false)
    }, 2000)
    return () => window.clearTimeout(timer)
  }, [lastPlayerHit, lastPlayerCrit, enemyHp])

  useEffect(() => {
    if (lastOffhandHit == null || lastOffhandHit <= 0) return
    setShownOffhandHit(lastOffhandHit)
    setOffhandHitOffset(randomDamageOffset())
    const timer = window.setTimeout(() => setShownOffhandHit(null), 2000)
    return () => window.clearTimeout(timer)
  }, [lastOffhandHit, enemyHp])

  useEffect(() => {
    if (lastEnemyHit == null || lastEnemyHit <= 0) return
    setShownEnemyHit(lastEnemyHit)
    setEnemyHitOffset(randomDamageOffset())
    const timer = window.setTimeout(() => setShownEnemyHit(null), 2000)
    return () => window.clearTimeout(timer)
  }, [lastEnemyHit, playerHp])

  useEffect(() => {
    if (defeatedFlash) {
      setShownPlayerHit(null)
      setShownOffhandHit(null)
      setShownEnemyHit(null)
    }
  }, [defeatedFlash])

  const roundPct = Math.round(roundProgress * 100)

  return (
    <section className="panel combat-panel" aria-label="Combat">
      <div className="combat-layout">
        <div className="combat-side combat-player-side">
          <div className="combat-float-slot">
            {shownEnemyHit != null && shownEnemyHit > 0 && !defeatedFlash && (
              <span
                className="combat-damage combat-damage-enemy"
                style={{
                  ['--damage-x' as string]: `${enemyHitOffset.x}px`,
                  ['--damage-y' as string]: `${enemyHitOffset.y}px`,
                }}
              >
                {shownEnemyHit}
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
                {shownPlayerHit != null && shownPlayerHit > 0 && (
                  <span
                    className={[
                      'combat-damage',
                      'combat-damage-player',
                      shownPlayerCrit ? 'combat-damage-crit' : '',
                    ]
                      .filter(Boolean)
                      .join(' ')}
                    style={{
                      ['--damage-x' as string]: `${playerHitOffset.x}px`,
                      ['--damage-y' as string]: `${playerHitOffset.y}px`,
                    }}
                  >
                    {shownPlayerCrit ? `CRIT ${shownPlayerHit}` : shownPlayerHit}
                  </span>
                )}
                {shownOffhandHit != null && shownOffhandHit > 0 && (
                  <span
                    className="combat-damage combat-damage-player combat-damage-offhand"
                    style={{
                      ['--damage-x' as string]: `${offhandHitOffset.x}px`,
                      ['--damage-y' as string]: `${offhandHitOffset.y}px`,
                    }}
                  >
                    {shownOffhandHit}
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
      {showRoundBar && (
        <div
          className="combat-round-bar"
          role="progressbar"
          aria-label="Round progress"
          aria-valuemin={0}
          aria-valuemax={100}
          aria-valuenow={roundPct}
        >
          <div
            className="combat-round-bar-fill"
            style={{ transform: `scaleX(${roundProgress})` }}
          />
        </div>
      )}
    </section>
  )
}
