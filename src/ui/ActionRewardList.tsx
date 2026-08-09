import { useEffect, useRef, useState, type ReactNode } from 'react'
import { itemAssetPath } from '../game/assets/itemAssets'
import type { ActionRewardBundle } from '../game/activity/types'
import type { ItemRow } from '../game/data/types'
import { SkillIcon } from './skillIcons'

interface ActionRewardListProps {
  rewards: ActionRewardBundle[]
  itemsById?: Map<string, ItemRow>
  /** How many recent action bundles to show. */
  limit?: number
  /** Compact HUD placement with hide control. */
  compact?: boolean
  hidden?: boolean
  onToggleHidden?: () => void
}

export function ActionRewardList({
  rewards,
  itemsById,
  limit = 3,
  compact = false,
  hidden = false,
  onToggleHidden,
}: ActionRewardListProps) {
  const [heldTip, setHeldTip] = useState<string | null>(null)
  const hasRewards = rewards.some((bundle) => {
    return bundle.xpRewards.length > 0 || bundle.loot.length > 0 || bundle.goldGained > 0
  })

  if (compact) {
    if (!hasRewards && !hidden) return null
    return (
      <section className="hud-reward-summary">
        <div className="hud-reward-summary-head">
          {!hidden && hasRewards ? (
            <span className="hud-reward-summary-title">Rewards</span>
          ) : (
            <span />
          )}
          {onToggleHidden && (
            <button
              type="button"
              className="btn secondary hud-reward-hide"
              onClick={onToggleHidden}
            >
              {hidden ? 'Show rewards' : 'Hide'}
            </button>
          )}
        </div>
        {!hidden && hasRewards && (
          <ul className="action-reward-list action-reward-list-compact">
            {rewards.slice(0, limit).map((bundle) => (
              <RewardRow
                key={bundle.id}
                bundle={bundle}
                itemsById={itemsById}
                heldTip={heldTip}
                setHeldTip={setHeldTip}
              />
            ))}
          </ul>
        )}
      </section>
    )
  }

  if (!hasRewards) return null

  return (
    <ul className="action-reward-list">
      {rewards.slice(0, limit).map((bundle) => (
        <RewardRow
          key={bundle.id}
          bundle={bundle}
          itemsById={itemsById}
          heldTip={heldTip}
          setHeldTip={setHeldTip}
        />
      ))}
    </ul>
  )
}

function RewardRow({
  bundle,
  itemsById,
  heldTip,
  setHeldTip,
}: {
  bundle: ActionRewardBundle
  itemsById?: Map<string, ItemRow>
  heldTip: string | null
  setHeldTip: (value: string | null | ((current: string | null) => string | null)) => void
}) {
  const levelUps = bundle.xpRewards.filter((reward) => reward.leveledUp)
  const hasContent =
    bundle.xpRewards.length > 0 || bundle.loot.length > 0 || bundle.goldGained > 0
  if (!hasContent) return null
  return (
    <li className="action-reward-row">
      <span className="action-reward-label">Reward:</span>
      {bundle.xpRewards.map((reward) => {
        const tipId = `${bundle.id}-xp-${reward.skillId}`
        return (
          <RewardTipChip
            key={tipId}
            tipId={tipId}
            tipText={reward.skillName}
            showingTip={heldTip === tipId}
            onTipStart={() => setHeldTip(tipId)}
            onTipEnd={() => setHeldTip((current) => (current === tipId ? null : current))}
          >
            <span className="action-reward-xp">{reward.xp.toLocaleString()}</span>
            <SkillIcon internalKey={reward.skillKey} title={reward.skillName} />
          </RewardTipChip>
        )
      })}
      {bundle.goldGained > 0 ? (
        <span className="action-reward-chip action-reward-gold">
          +{bundle.goldGained.toLocaleString()} gold
        </span>
      ) : null}
      {bundle.loot.map((loot, index) => {
        const tipId = `${bundle.id}-loot-${loot.itemId}-${index}`
        return (
          <RewardTipChip
            key={tipId}
            tipId={tipId}
            tipText={loot.displayName}
            showingTip={heldTip === tipId}
            onTipStart={() => setHeldTip(tipId)}
            onTipEnd={() => setHeldTip((current) => (current === tipId ? null : current))}
          >
            <span className="action-reward-xp">+{loot.quantity}</span>
            <span
              className="item-icon item-icon-art action-reward-item-icon"
              style={{
                backgroundImage: `url(${itemAssetPath(itemsById?.get(loot.itemId) ?? loot.itemId)})`,
              }}
              aria-hidden
            />
          </RewardTipChip>
        )
      })}
      {levelUps.map((reward) => (
        <span key={`${bundle.id}-lvl-${reward.skillId}`} className="action-reward-level">
          level {reward.level} {reward.skillName} achieved
        </span>
      ))}
    </li>
  )
}

function RewardTipChip({
  tipId: _tipId,
  tipText,
  showingTip,
  onTipStart,
  onTipEnd,
  children,
}: {
  tipId: string
  tipText: string
  showingTip: boolean
  onTipStart: () => void
  onTipEnd: () => void
  children: ReactNode
}) {
  const timerRef = useRef<number | null>(null)

  useEffect(() => {
    return () => {
      if (timerRef.current != null) window.clearTimeout(timerRef.current)
    }
  }, [])

  function clearTimer() {
    if (timerRef.current != null) {
      window.clearTimeout(timerRef.current)
      timerRef.current = null
    }
  }

  function beginTip() {
    clearTimer()
    timerRef.current = window.setTimeout(() => {
      onTipStart()
    }, 120)
  }

  function endTip() {
    clearTimer()
    onTipEnd()
  }

  return (
    <button
      type="button"
      className={
        showingTip
          ? 'action-reward-chip action-reward-chip-tip showing-tip'
          : 'action-reward-chip action-reward-chip-tip'
      }
      aria-label={tipText}
      onPointerDown={beginTip}
      onPointerUp={endTip}
      onPointerLeave={endTip}
      onPointerCancel={endTip}
      onPointerEnter={beginTip}
      onFocus={onTipStart}
      onBlur={endTip}
      onContextMenu={(event) => event.preventDefault()}
    >
      {children}
      {showingTip ? (
        <span className="item-name-tooltip action-reward-tooltip" role="tooltip">
          {tipText}
        </span>
      ) : null}
    </button>
  )
}
