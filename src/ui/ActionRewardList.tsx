import type { ActionXpRewardSummary } from '../game/activity/types'
import { SkillIcon } from './skillIcons'

interface ActionRewardListProps {
  rewards: ActionXpRewardSummary[]
  limit?: number
}

export function ActionRewardList({ rewards, limit = 6 }: ActionRewardListProps) {
  if (rewards.length === 0) return null
  return (
    <ul className="action-reward-list">
      {rewards.slice(0, limit).map((reward, index) => (
        <li key={`${reward.skillId}-${reward.xp}-${index}`} className="action-reward-row">
          <span className="action-reward-label">Reward:</span>
          <span className="action-reward-xp">{reward.xp.toLocaleString()}</span>
          <SkillIcon internalKey={reward.skillKey} title={reward.skillName} />
          {reward.leveledUp ? (
            <span className="action-reward-level">
              level {reward.level} {reward.skillName} achieved
            </span>
          ) : null}
        </li>
      ))}
    </ul>
  )
}
