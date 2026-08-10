import { useState } from 'react'
import type { GameDatabase, NpcRow } from '../game/data/types'
import { applyXp } from '../game/activity/xp'
import {
  ARCHMAGE_ID,
  MASTER_DWARF_ID,
  hasNpcKnowledge,
  unlockNpcKnowledge,
} from '../game/npcs/knowledge'
import { questObjectiveProgress } from '../game/quests/objectives'
import {
  acceptQuest,
  completeQuest,
  getQuestProgress,
  questsForNpc,
  type QuestRewardLine,
} from '../game/quests/quests'
import type { PlayerSave } from '../game/save/types'
import { QuestRewardPopup } from './QuestRewardPopup'

const GENERAL_STORE_MERCHANT_ID = 'NPC-0007'
const ARTISANRY_SKILL_ID = 'SKL-0012'
const MERCHANT_ARTISANRY_TIP_XP = 11_000
const ROSE_NPC_ID = 'NPC-0005'
const ROSE_QUEST_ID = 'QST-0002'

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
  const isGeneralStoreMerchant = npc['NPC ID'] === GENERAL_STORE_MERCHANT_ID
  const isRose = npc['NPC ID'] === ROSE_NPC_ID
  const knowsMentor = hasNpcKnowledge(save, npc['NPC ID'])
  const [rewardPopup, setRewardPopup] = useState<{
    questName: string
    rewards: QuestRewardLine[]
  } | null>(null)
  const tipClaimed = (save.claimedMerchantTipIds ?? []).includes(npc['NPC ID'])
  const [merchantDialogueOpen, setMerchantDialogueOpen] = useState(isMerchant)
  const roseQuest = quests.find((quest) => quest['Quest ID'] === ROSE_QUEST_ID)
  const roseProgress = roseQuest ? getQuestProgress(save, ROSE_QUEST_ID) : null
  const [rosePitchOpen, setRosePitchOpen] = useState(
    Boolean(isRose && roseQuest && roseProgress?.status === 'inactive'),
  )

  if (isMerchant) {
    const tipLine = isGeneralStoreMerchant
      ? tipClaimed
        ? 'I’ve already shared what I know about artisanry.'
        : 'Here’s some tips about artisanry'
      : npc.Description ?? 'Welcome to my shop.'
    const tipDetail =
      isGeneralStoreMerchant && !tipClaimed
        ? `${MERCHANT_ARTISANRY_TIP_XP.toLocaleString()} Artisanry XP`
        : null

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
              <p className="lead">{tipLine}</p>
              {tipDetail && <p className="muted">{tipDetail}</p>}
              <button
                type="button"
                className="btn primary"
                onClick={() => {
                  if (isGeneralStoreMerchant && !tipClaimed) {
                    const applied = applyXp(save, db, ARTISANRY_SKILL_ID, MERCHANT_ARTISANRY_TIP_XP)
                    onChangeSave(
                      {
                        ...applied.save,
                        claimedMerchantTipIds: [
                          ...(save.claimedMerchantTipIds ?? []),
                          npc['NPC ID'],
                        ],
                        updatedAt: new Date().toISOString(),
                      },
                      `Learned artisanry tips (+${MERCHANT_ARTISANRY_TIP_XP.toLocaleString()} XP).`,
                    )
                  }
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

  if (isRose && rosePitchOpen && roseQuest && roseProgress?.status === 'inactive') {
    return (
      <div
        className="quest-reward-overlay"
        role="dialog"
        aria-modal="true"
        aria-labelledby="rose-dialogue-title"
      >
        <div className="panel quest-reward-card">
          <h2 id="rose-dialogue-title">{npc['Display Name']}</h2>
          <p className="lead">
            I’m tired of working in the kitchen, I just saw a lot for sale down the street, I’m
            thinking of starting the alchemy shop I’ve always dreamed of…
          </p>
          <div className="button-row" style={{ justifyContent: 'center' }}>
            <button
              type="button"
              className="btn secondary"
              onClick={() => {
                setRosePitchOpen(false)
                onClose()
              }}
            >
              Not now
            </button>
            <button
              type="button"
              className="btn primary"
              onClick={() => {
                const result = acceptQuest(db, save, ROSE_QUEST_ID)
                if (!result.ok) {
                  onChangeSave(save, result.reason)
                  return
                }
                setRosePitchOpen(false)
                onChangeSave(result.save, `Started quest: ${roseQuest['Display Name']}.`)
              }}
            >
              Start quest: Help the aspiring apothecary
            </button>
          </div>
        </div>
      </div>
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
          const objective = questObjectiveProgress(db, save, quest)

          return (
            <div key={quest['Quest ID']} className="npc-quest-block">
              <h3>{quest['Display Name']}</h3>
              <p className="lead">{quest.Summary}</p>
              {progress.status === 'completed' ? (
                <p className="muted">
                  {quest['Quest ID'] === ROSE_QUEST_ID
                    ? 'Completed — Rose’s Apothecary is open on the Town Map.'
                    : 'Completed.'}
                </p>
              ) : progress.status === 'inactive' ? (
                <button
                  type="button"
                  className="btn primary"
                  onClick={() => {
                    if (quest['Quest ID'] === ROSE_QUEST_ID) {
                      setRosePitchOpen(true)
                      return
                    }
                    const result = acceptQuest(db, save, quest['Quest ID'])
                    if (!result.ok) {
                      onChangeSave(save, result.reason)
                      return
                    }
                    onChangeSave(result.save, `Accepted: ${quest['Display Name']}.`)
                  }}
                >
                  {quest['Quest ID'] === ROSE_QUEST_ID
                    ? 'Start quest: Help the aspiring apothecary'
                    : 'Accept quest'}
                </button>
              ) : (
                <>
                  {objective.lines.map((line) => (
                    <p key={line.itemId} className="muted tiny">
                      Progress: {Math.min(line.owned, line.required)} / {line.required} {line.name}
                    </p>
                  ))}
                  {objective.goldRequired > 0 && (
                    <p className="muted tiny">
                      Gold: {objective.goldOwned.toLocaleString()} /{' '}
                      {objective.goldRequired.toLocaleString()}
                    </p>
                  )}
                  <button
                    type="button"
                    className="btn primary"
                    disabled={!objective.ready}
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
