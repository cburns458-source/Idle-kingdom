import type { QuestRewardLine } from '../game/quests/quests'

interface QuestRewardPopupProps {
  questName: string
  rewards: QuestRewardLine[]
  onClose: () => void
}

export function QuestRewardPopup({ questName, rewards, onClose }: QuestRewardPopupProps) {
  return (
    <div className="quest-reward-overlay" role="dialog" aria-modal="true" aria-labelledby="quest-reward-title">
      <div className="panel quest-reward-card">
        <p className="muted tiny">Quest complete</p>
        <h2 id="quest-reward-title">{questName}</h2>
        {rewards.length > 0 ? (
          <>
            <p className="lead">Rewards</p>
            <ul className="quest-reward-list">
              {rewards.map((reward) => (
                <li key={reward.label}>{reward.label}</li>
              ))}
            </ul>
          </>
        ) : (
          <p className="lead">No listed rewards.</p>
        )}
        <button type="button" className="btn primary" onClick={onClose}>
          Continue
        </button>
      </div>
    </div>
  )
}
