import { useState } from 'react'
import { asAchievementRows } from '../game/achievements/progress'
import { CRITTER_DEFS, collectionCount } from '../game/critters/critters'
import type { LoadedDatabase } from '../game/data/loadDatabase'
import { asQuestRows, getQuestProgress, questStatusLabel } from '../game/quests/quests'
import type { PlayerSave } from '../game/save/types'

type LogTab = 'achievements' | 'quests' | 'critters'

interface LogViewProps {
  save: PlayerSave
  database: LoadedDatabase
}

export function LogView({ save, database }: LogViewProps) {
  const [tab, setTab] = useState<LogTab>('achievements')
  const achievements = asAchievementRows(database.launch)
  const quests = asQuestRows(database.launch)

  return (
    <section className="panel menu-panel log-panel">
      <h1>Log</h1>
      <div className="menu-tabs log-tabs" role="tablist" aria-label="Log sections">
        <button
          type="button"
          role="tab"
          aria-selected={tab === 'achievements'}
          className={tab === 'achievements' ? 'menu-tab active' : 'menu-tab'}
          onClick={() => setTab('achievements')}
        >
          Achievements
        </button>
        <button
          type="button"
          role="tab"
          aria-selected={tab === 'quests'}
          className={tab === 'quests' ? 'menu-tab active' : 'menu-tab'}
          onClick={() => setTab('quests')}
        >
          Quests
        </button>
        <button
          type="button"
          role="tab"
          aria-selected={tab === 'critters'}
          className={tab === 'critters' ? 'menu-tab active' : 'menu-tab'}
          onClick={() => setTab('critters')}
        >
          Critters
        </button>
      </div>

      {tab === 'achievements' && (
        <div role="tabpanel" className="menu-tab-panel">
          <p className="lead">Skill milestones unlocked on this save.</p>
          <ul className="achievement-list">
            {achievements.map((achievement) => {
              const unlocked = save.achievements.some(
                (row) => row.achievementId === achievement['Achievement ID'] && row.unlocked,
              )
              const skillName =
                database.launch.Skills.find(
                  (skill) => skill['Skill ID'] === achievement['Target Skill ID'],
                )?.['Display Name'] ?? 'Skill'
              return (
                <li
                  key={achievement['Achievement ID']}
                  className={unlocked ? 'unlocked' : undefined}
                >
                  <strong>{achievement['Display Name']}</strong>
                  <span className="muted tiny">
                    {unlocked
                      ? 'Unlocked'
                      : `Reach ${skillName} level ${achievement['Required Level'] ?? 50}`}
                  </span>
                </li>
              )
            })}
          </ul>
        </div>
      )}

      {tab === 'quests' && (
        <div role="tabpanel" className="menu-tab-panel">
          <p className="lead">Quest log for this save.</p>
          <ul className="achievement-list quest-log-list">
            {quests.map((quest) => {
              const progress = getQuestProgress(save, quest['Quest ID'])
              const npcName =
                database.launch.NPCs.find((npc) => npc['NPC ID'] === quest['NPC ID'])?.[
                  'Display Name'
                ] ?? 'NPC'
              return (
                <li
                  key={quest['Quest ID']}
                  className={progress.status === 'completed' ? 'unlocked' : undefined}
                >
                  <div className="quest-log-copy">
                    <strong>{quest['Display Name']}</strong>
                    <span className="muted tiny">
                      {quest.Summary ?? 'No summary.'} · {npcName}
                    </span>
                  </div>
                  <span className="muted tiny">{questStatusLabel(progress.status)}</span>
                </li>
              )
            })}
          </ul>
        </div>
      )}

      {tab === 'critters' && (
        <div role="tabpanel" className="menu-tab-panel">
          <p className="lead">Critters found while working their habitats.</p>
          <ul className="achievement-list critter-log-list">
            {CRITTER_DEFS.map((critter) => {
              const count = collectionCount(save, critter.id)
              return (
                <li key={critter.id} className={count > 0 ? 'unlocked' : undefined}>
                  <div className="quest-log-copy">
                    <strong>{critter.displayName}</strong>
                    <span className="muted tiny">{critter.description}</span>
                  </div>
                  <span className="muted tiny">
                    {count <= 0 ? 'Not found' : count === 1 ? 'Found' : `×${count}`}
                  </span>
                </li>
              )
            })}
          </ul>
        </div>
      )}
    </section>
  )
}
