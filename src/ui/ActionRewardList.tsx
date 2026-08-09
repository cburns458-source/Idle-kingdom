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
            {bundle.xpRewards.map((reward) => (
              <span key={`${bundle.id}-${reward.skillId}`} className="action-reward-chip">
                <span className="action-reward-xp">{reward.xp.toLocaleString()}</span>
                <SkillIcon internalKey={reward.skillKey} title={reward.skillName} />
              </span>
            ))}
            {bundle.goldGained > 0 ? (
              <span className="action-reward-chip action-reward-gold">
                +{bundle.goldGained.toLocaleString()} gold
              </span>
            ) : null}
            {bundle.loot.map((loot, index) => (
              <span
                key={`${bundle.id}-${loot.itemId}-${index}`}
                className="action-reward-chip"
                title={`${loot.displayName} ×${loot.quantity}`}
                aria-label={`${loot.displayName} ×${loot.quantity}`}
              >
                <span className="action-reward-xp">+{loot.quantity}</span>
                <span
                  className="item-icon item-icon-art action-reward-item-icon"
                  style={{
                    backgroundImage: `url(${itemAssetPath(itemsById?.get(loot.itemId) ?? loot.itemId)})`,
                  }}
                  aria-hidden
                />
              </span>
            ))}
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
