import { useEffect, useRef, useState } from 'react'
import type { GameDatabase, NpcRow } from '../game/data/types'
import {
  ARCHMAGE_ID,
  MASTER_DWARF_ID,
  hasNpcKnowledge,
  unlockNpcKnowledge,
} from '../game/npcs/knowledge'
import {
  acceptQuest,
  completeQuest,
  getQuestProgress,
  questsForNpc,
  type QuestRewardLine,
} from '../game/quests/quests'
import type { PlayerSave } from '../game/save/types'
import { inventoryCount } from '../game/production/recipes'
import { QuestRewardPopup } from './QuestRewardPopup'

const MERCHANT_TIP_GOLD = 1000

interface NpcPanelProps {
  db: GameDatabase
  save: PlayerSave
  npc: NpcRow
  onClose: () => void
  onChangeSave: (save: PlayerSave, message: string | null) => void
  onOpenShop?: (shopId: string) => void
}

export function NpcPanel({
  db,
  save,
  npc,
  onClose,
  onChangeSave,
}: NpcPanelProps) {
  const quests = questsForNpc(db, npc['NPC ID'])
  const isMentor = npc['NPC ID'] === MASTER_DWARF_ID || npc['NPC ID'] === ARCHMAGE_ID
  const isMerchant = (npc.Role ?? '').toLowerCase() === 'merchant'
  const knowsMentor = hasNpcKnowledge(save, npc['NPC ID'])
  const [rewardPopup, setRewardPopup] = useState<{
    questName: string
    rewards: QuestRewardLine[]
  } | null>(null)
  const [merchantDialogueOpen, setMerchantDialogueOpen] = useState(isMerchant)
  const merchantTipGranted = useRef(false)

  useEffect(() => {
    if (!isMerchant || merchantTipGranted.current) return
    merchantTipGranted.current = true
    onChangeSave(
      {
        ...save,
        gold: save.gold + MERCHANT_TIP_GOLD,
        updatedAt: new Date().toISOString(),
      },
      null,
    )
    setMerchantDialogueOpen(true)
    // Grant once when this merchant talk session opens.
    // eslint-disable-next-line react-hooks/exhaustive-deps -- intentional mount-only tip
  }, [npc['NPC ID']])

  if (isMerchant) {
    return (
      <>
        {merchantDialogueOpen && (
          <div
            className="quest-reward-overlay"
            role="dialog"
            aria-modal="true"
            aria-labelledby="merchant-dialogue-title"
          >
            <div className="panel quest-reward-card">
              <h2 id="merchant-dialogue-title">{npc['Display Name']}</h2>
              <p className="lead">Good luck!</p>
              <p className="muted">+{MERCHANT_TIP_GOLD.toLocaleString()} gold</p>
              <button
                type="button"
                className="btn primary"
                onClick={() => {
                  setMerchantDialogueOpen(false)
                  onClose()
                }}
              >
                Continue
              </button>
            </div>
          </div>
        )}
      </>
    )
  }

  return (
    <>
      <section className="panel glass-panel npc-panel">
        <div className="activity-panel-head">
          <div>
            <h2>{npc['Display Name']}</h2>
            {npc.Role && <p className="muted tiny">{npc.Role}</p>}
            <p className="lead">{npc.Description ?? 'An inhabitant of Idale.'}</p>
          </div>
          <button type="button" className="btn secondary" onClick={onClose}>
            Close
          </button>
        </div>

        {isMentor && (
          <div className="npc-action-block">
            {knowsMentor ? (
              <p className="muted">
                {npc['NPC ID'] === MASTER_DWARF_ID
                  ? 'Smithing projects are unlocked.'
                  : 'Arcana projects are unlocked.'}
              </p>
            ) : (
              <button
                type="button"
                className="btn primary"
                onClick={() => {
                  const result = unlockNpcKnowledge(save, npc['NPC ID'])
                  if (!result.ok) {
                    onChangeSave(save, result.reason)
                    return
                  }
                  onChangeSave(
                    result.save,
                    npc['NPC ID'] === MASTER_DWARF_ID
                      ? 'The Master Dwarf unlocks all Smithing projects.'
                      : 'The Archmage unlocks all Arcana projects.',
                  )
                }}
              >
                {npc['NPC ID'] === MASTER_DWARF_ID
                  ? 'Learn Smithing projects'
                  : 'Learn Arcana projects'}
              </button>
            )}
          </div>
        )}

        {quests.map((quest) => {
          const progress = getQuestProgress(save, quest['Quest ID'])
          const targetId = quest['Objective Target ID']
          const required = quest['Required Quantity'] ?? 0
          const owned = targetId ? inventoryCount(save, targetId) : 0
          const targetName = targetId
            ? (db.Items.find((item) => item['Item ID'] === targetId)?.['Display Name'] ?? targetId)
            : 'items'

          return (
            <div key={quest['Quest ID']} className="npc-quest-block">
              <h3>{quest['Display Name']}</h3>
              <p className="lead">{quest.Summary}</p>
              {progress.status === 'completed' ? (
                <p className="muted">Completed.</p>
              ) : progress.status === 'inactive' ? (
                <button
                  type="button"
                  className="btn primary"
                  onClick={() => {
                    const result = acceptQuest(db, save, quest['Quest ID'])
                    if (!result.ok) {
                      onChangeSave(save, result.reason)
                      return
                    }
                    onChangeSave(result.save, `Accepted: ${quest['Display Name']}.`)
                  }}
                >
                  Accept quest
                </button>
              ) : (
                <>
                  <p className="muted tiny">
                    Progress: {Math.min(owned, required)} / {required} {targetName}
                  </p>
                  <button
                    type="button"
                    className="btn primary"
                    disabled={owned < required}
                    onClick={() => {
                      const result = completeQuest(db, save, quest['Quest ID'])
                      if (!result.ok) {
                        onChangeSave(save, result.reason)
                        return
                      }
                      onChangeSave(result.save, result.message)
                      setRewardPopup({
                        questName: result.questName,
                        rewards: result.rewards,
                      })
                    }}
                  >
                    Turn in
                  </button>
                </>
              )}
            </div>
          )
        })}

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
