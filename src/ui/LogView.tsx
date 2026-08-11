import { useState } from 'react'
import { asAchievementRows } from '../game/achievements/progress'
import { critterAssetPath } from '../game/assets/critterAssets'
import { CRITTER_DEFS, collectionCount } from '../game/critters/critters'
import type { LoadedDatabase } from '../game/data/loadDatabase'
import { asQuestRows, getQuestProgress, questStatusLabel } from '../game/quests/quests'
import { questObjectiveProgress } from '../game/quests/objectives'
import { listRecipeBookEntries } from '../game/recipes/knowledge'
import type { PlayerSave } from '../game/save/types'

type LogTab = 'achievements' | 'quests' | 'recipes' | 'critters'

interface LogViewProps {
  save: PlayerSave
  database: LoadedDatabase
}

export function LogView({ save, database }: LogViewProps) {
  const [tab, setTab] = useState<LogTab>('achievements')
  const achievements = asAchievementRows(database.launch)
  const quests = asQuestRows(database.launch)
  const recipes = listRecipeBookEntries(save, database.launch)

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
          aria-selected={tab === 'recipes'}
          className={tab === 'recipes' ? 'menu-tab active' : 'menu-tab'}
          onClick={() => setTab('recipes')}
        >
          Recipe Book
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
              const objectives =
                progress.status === 'active'
                  ? questObjectiveProgress(database.launch, save, quest)
                  : null
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
                    {objectives && objectives.progressLines.length > 0 && (
                      <ul className="quest-objective-list">
                        {objectives.progressLines.map((line) => {
                          const pct = Math.min(
                            100,
                            Math.floor((line.current / Math.max(1, line.required)) * 100),
                          )
                          return (
                            <li key={line.key} className="quest-objective-row">
                              <span className="muted tiny">
                                {line.label}: {Math.min(line.current, line.required)}/
                                {line.required}
                              </span>
                              <span
                                className="quest-progress-bar"
                                role="progressbar"
                                aria-valuenow={pct}
                                aria-valuemin={0}
                                aria-valuemax={100}
                              >
                                <span style={{ width: `${pct}%` }} />
                              </span>
                            </li>
                          )
                        })}
                      </ul>
                    )}
                  </div>
                  <span className="muted tiny">{questStatusLabel(progress.status)}</span>
                </li>
              )
            })}
          </ul>
        </div>
      )}

      {tab === 'recipes' && (
        <div role="tabpanel" className="menu-tab-panel">
          <p className="lead">Known recipes and special projects for this save.</p>
          <ul className="achievement-list recipe-book-list">
            {recipes.map((entry) => (
              <li
                key={`${entry.kind}-${entry.id}`}
                className={entry.known ? 'unlocked' : 'recipe-unknown'}
              >
                <span
                  className={entry.known ? 'recipe-book-mark' : 'recipe-book-mark unknown'}
                  aria-hidden
                />
                <div className="quest-log-copy">
                  <strong>
                    {entry.known
                      ? entry.name
                      : entry.hintUnknown
                        ? 'Unknown recipe'
                        : `Locked · ${entry.skill} ${entry.proficiency}`}
                  </strong>
                  {entry.known ? (
                    <span className="muted tiny">
                      {entry.kind === 'project' ? 'Project' : 'Recipe'} · {entry.skill}{' '}
                      {entry.proficiency} · {entry.station} ({entry.location}) · {entry.materials} →{' '}
                      {entry.output}
                    </span>
                  ) : (
                    <span className="muted tiny">
                      {entry.hintUnknown
                        ? entry.knowledgeSource
                        : `Unlocks at ${entry.skill} level ${entry.proficiency}`}
                    </span>
                  )}
                </div>
              </li>
            ))}
          </ul>
        </div>
      )}

      {tab === 'critters' && (
        <div role="tabpanel" className="menu-tab-panel">
          <p className="lead">Critters found while working their habitats.</p>
          <ul className="achievement-list critter-log-list">
            {CRITTER_DEFS.map((critter) => {
              const count = collectionCount(save, critter.id)
              const found = count > 0
              return (
                <li key={critter.id} className={found ? 'unlocked' : undefined}>
                  <span
                    className={found ? 'critter-log-avatar' : 'critter-log-avatar unknown'}
                    style={
                      found
                        ? { backgroundImage: `url(${critterAssetPath(critter.internalKey)})` }
                        : undefined
                    }
                    aria-hidden
                  />
                  <div className="quest-log-copy">
                    <strong>{found ? critter.displayName : 'Unknown'}</strong>
                    {found && <span className="muted tiny">{critter.description}</span>}
                  </div>
                  {found && count > 1 && <span className="muted tiny">×{count}</span>}
                </li>
              )
            })}
          </ul>
        </div>
      )}
    </section>
  )
}
