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
}

export function ActionRewardList({
  rewards,
  itemsById,
  limit = 3,
}: ActionRewardListProps) {
  const [heldTip, setHeldTip] = useState<string | null>(null)
  if (rewards.length === 0) return null
  return (
    <ul className="action-reward-list">
      {rewards.slice(0, limit).map((bundle) => {
        const levelUps = bundle.xpRewards.filter((reward) => reward.leveledUp)
        const hasContent =
          bundle.xpRewards.length > 0 || bundle.loot.length > 0 || bundle.goldGained > 0
        if (!hasContent) return null
        return (
          <li key={bundle.id} className="action-reward-row">
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
              const tipText = loot.displayName
              return (
                <RewardTipChip
                  key={tipId}
                  tipId={tipId}
                  tipText={tipText}
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
      })}
    </ul>
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
        showingTip ? 'action-reward-chip action-reward-chip-tip showing-tip' : 'action-reward-chip action-reward-chip-tip'
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
