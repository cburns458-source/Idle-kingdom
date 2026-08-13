import { useState } from 'react'
import type { GameDatabase, NpcRow } from '../game/data/types'
import {
  acceptQuestFromNpc,
  learnMentorProjects,
  npcConversation,
  takeMerchantTip,
  type NpcQuestBlock,
} from '../game/npcs/conversation'
import { completeQuest, type QuestRewardLine } from '../game/quests/quests'
import type { PlayerSave } from '../game/save/types'
import { CloseButton } from './CloseButton'
import { QuestRewardPopup } from './QuestRewardPopup'

interface NpcPanelProps {
  db: GameDatabase
  save: PlayerSave
  npc: NpcRow
  onClose: () => void
  onChangeSave: (save: PlayerSave, message: string | null) => void
  onOpenShop?: (shopId: string) => void
}

export function NpcPanel({ db, save, npc, onClose, onChangeSave }: NpcPanelProps) {
  const conversation = npcConversation(db, save, npc)
  const greeting = conversation.greeting
  const [rewardPopup, setRewardPopup] = useState<{
    questName: string
    rewards: QuestRewardLine[]
  } | null>(null)
  const [dialogueOpen, setDialogueOpen] = useState(greeting !== null)
  const [pitchQuestId, setPitchQuestId] = useState<string | null>(
    greeting?.kind === 'quest_pitch' ? greeting.questId : null,
  )

  const accept = (questId: string) => {
    const result = acceptQuestFromNpc(db, save, questId)
    if (!result.ok) {
      onChangeSave(save, result.reason)
      return
    }
    setPitchQuestId(null)
    setDialogueOpen(false)
    onChangeSave(result.save, result.message)
  }

  if (greeting?.kind === 'merchant') {
    const dismiss = () => {
      const claimed = takeMerchantTip(db, save, conversation.npcId)
      if (claimed) {
        onChangeSave({ ...claimed.save, updatedAt: new Date().toISOString() }, claimed.message)
      }
      setDialogueOpen(false)
      onClose()
    }

    if (!dialogueOpen) return null
    return (
      <div
        className="quest-reward-overlay"
        role="dialog"
        aria-modal="true"
        aria-labelledby="merchant-dialogue-title"
        onClick={(event) => {
          if (event.target === event.currentTarget) dismiss()
        }}
      >
        <div className="panel quest-reward-card">
          <h2 id="merchant-dialogue-title">{conversation.name}</h2>
          <p className="lead">{greeting.line}</p>
          {greeting.detail && <p className="muted">{greeting.detail}</p>}
          <button type="button" className="btn primary" onClick={dismiss}>
            Continue
          </button>
        </div>
      </div>
    )
  }

  const pitched = conversation.quests.find(
    (quest) =>
      quest.questId === pitchQuestId && quest.status === 'inactive' && quest.pitchLine !== null,
  )
  if (dialogueOpen && pitched?.pitchLine) {
    const dismiss = () => {
      setPitchQuestId(null)
      setDialogueOpen(false)
      onClose()
    }
    return (
      <div
        className="quest-reward-overlay"
        role="dialog"
        aria-modal="true"
        aria-labelledby="npc-pitch-title"
        onClick={(event) => {
          if (event.target === event.currentTarget) dismiss()
        }}
      >
        <div className="panel quest-reward-card">
          <h2 id="npc-pitch-title">{conversation.name}</h2>
          <p className="lead">{pitched.pitchLine}</p>
          <div className="button-row" style={{ justifyContent: 'center' }}>
            <button type="button" className="btn secondary" onClick={dismiss}>
              Not now
            </button>
            <button type="button" className="btn primary" onClick={() => accept(pitched.questId)}>
              {pitched.acceptLabel}
            </button>
          </div>
        </div>
      </div>
    )
  }

  const turnIn = (quest: NpcQuestBlock) => {
    const result = completeQuest(db, save, quest.questId)
    if (!result.ok) {
      onChangeSave(save, result.reason)
      return
    }
    onChangeSave(result.save, result.message)
    setRewardPopup({ questName: result.questName, rewards: result.rewards })
  }

  return (
    <>
      <section className="panel glass-panel npc-panel">
        <div className="activity-panel-head">
          <div>
            <h2>{conversation.name}</h2>
            {conversation.role && <p className="muted tiny">{conversation.role}</p>}
            <p className="lead">{conversation.description}</p>
          </div>
          <CloseButton onClick={onClose} />
        </div>

        {conversation.mentor && (
          <div className="npc-action-block">
            {conversation.mentor.known ? (
              <p className="muted">{conversation.mentor.knownNote}</p>
            ) : (
              <button
                type="button"
                className="btn primary"
                onClick={() => {
                  const result = learnMentorProjects(db, save, conversation.npcId)
                  if (!result.ok) {
                    onChangeSave(save, result.reason)
                    return
                  }
                  onChangeSave(result.save, result.message)
                }}
              >
                {conversation.mentor.learnLabel}
              </button>
            )}
          </div>
        )}

        {conversation.quests.map((quest) => (
          <div key={quest.questId} className="npc-quest-block">
            <h3>{quest.name}</h3>
            <p className="lead">{quest.summary}</p>
            {quest.status === 'completed' ? (
              <p className="muted">{quest.completedNote}</p>
            ) : quest.status === 'inactive' ? (
              <button
                type="button"
                className="btn primary"
                onClick={() => {
                  if (quest.pitchLine !== null) {
                    setPitchQuestId(quest.questId)
                    setDialogueOpen(true)
                    return
                  }
                  accept(quest.questId)
                }}
              >
                {quest.acceptLabel}
              </button>
            ) : (
              <>
                {quest.lines.map((line) => (
                  <p key={line.itemId} className="muted tiny">
                    Progress: {Math.min(line.owned, line.required)} / {line.required} {line.name}
                  </p>
                ))}
                {quest.goldRequired > 0 && (
                  <p className="muted tiny">
                    Gold: {quest.goldOwned.toLocaleString()} / {quest.goldRequired.toLocaleString()}
                  </p>
                )}
                <button
                  type="button"
                  className="btn primary"
                  disabled={!quest.ready}
                  onClick={() => turnIn(quest)}
                >
                  Turn in
                </button>
              </>
            )}
          </div>
        ))}
      </section>

      {rewardPopup && (
        <QuestRewardPopup
          questName={rewardPopup.questName}
          rewards={rewardPopup.rewards}
          onClose={() => setRewardPopup(null)}
        />
      )}
    </>
  )
}
