import { useState } from 'react'
import { critterAssetPath } from '../game/assets/critterAssets'
import type { LoadedDatabase } from '../game/data/loadDatabase'
import { achievementLog, critterLog, questLog, recipeLog } from '../game/log/log'
import type { PlayerSave } from '../game/save/types'

type LogTab = 'achievements' | 'quests' | 'recipes' | 'critters'

const TABS: { id: LogTab; label: string; lead: string }[] = [
  {
    id: 'achievements',
    label: 'Achievements',
    lead: 'Skill milestones unlocked on this save.',
  },
  { id: 'quests', label: 'Quests', lead: 'Quest log for this save.' },
  {
    id: 'recipes',
    label: 'Recipe Book',
    lead: 'Known recipes and special projects for this save.',
  },
  { id: 'critters', label: 'Critters', lead: 'Critters found while working their habitats.' },
]

interface LogViewProps {
  save: PlayerSave
  database: LoadedDatabase
}

export function LogView({ save, database }: LogViewProps) {
  const [tab, setTab] = useState<LogTab>('achievements')
  const db = database.launch
  const active = TABS.find((entry) => entry.id === tab) ?? TABS[0]!

  return (
    <section className="panel menu-panel log-panel">
      <h1>Log</h1>
      <div className="menu-tabs log-tabs" role="tablist" aria-label="Log sections">
        {TABS.map((entry) => (
          <button
            key={entry.id}
            type="button"
            role="tab"
            aria-selected={tab === entry.id}
            className={tab === entry.id ? 'menu-tab active' : 'menu-tab'}
            onClick={() => setTab(entry.id)}
          >
            {entry.label}
          </button>
        ))}
      </div>

      <div role="tabpanel" className="menu-tab-panel">
        <p className="lead">{active.lead}</p>

        {tab === 'achievements' && (
          <ul className="achievement-list">
            {achievementLog(db, save).map((row) => (
              <li key={row.achievementId} className={row.unlocked ? 'unlocked' : undefined}>
                <strong>{row.name}</strong>
                <span className="muted tiny">{row.note}</span>
              </li>
            ))}
          </ul>
        )}

        {tab === 'quests' && (
          <ul className="achievement-list quest-log-list">
            {questLog(db, save).map((row) => (
              <li key={row.questId} className={row.completed ? 'unlocked' : undefined}>
                <div className="quest-log-copy">
                  <strong>{row.name}</strong>
                  <span className="muted tiny">{row.detail}</span>
                  {row.objectives.length > 0 && (
                    <ul className="quest-objective-list">
                      {row.objectives.map((objective) => (
                        <li key={objective.key} className="quest-objective-row">
                          <span className="muted tiny">{objective.label}</span>
                          <span
                            className="quest-progress-bar"
                            role="progressbar"
                            aria-valuenow={objective.percent}
                            aria-valuemin={0}
                            aria-valuemax={100}
                          >
                            <span style={{ width: `${objective.percent}%` }} />
                          </span>
                        </li>
                      ))}
                    </ul>
                  )}
                </div>
                <span className="muted tiny">{row.statusLabel}</span>
              </li>
            ))}
          </ul>
        )}

        {tab === 'recipes' && (
          <ul className="achievement-list recipe-book-list">
            {recipeLog(db, save).map((row) => (
              <li key={row.key} className={row.known ? 'unlocked' : 'recipe-unknown'}>
                <span
                  className={row.known ? 'recipe-book-mark' : 'recipe-book-mark unknown'}
                  aria-hidden
                />
                <div className="quest-log-copy">
                  <strong>{row.title}</strong>
                  <span className="muted tiny">{row.detail}</span>
                </div>
              </li>
            ))}
          </ul>
        )}

        {tab === 'critters' && (
          <ul className="achievement-list critter-log-list">
            {critterLog(save).map((row) => (
              <li key={row.critterId} className={row.found ? 'unlocked' : undefined}>
                <span
                  className={row.found ? 'critter-log-avatar' : 'critter-log-avatar unknown'}
                  style={
                    row.found
                      ? { backgroundImage: `url(${critterAssetPath(row.internalKey)})` }
                      : undefined
                  }
                  aria-hidden
                />
                <div className="quest-log-copy">
                  <strong>{row.name}</strong>
                  {row.description && <span className="muted tiny">{row.description}</span>}
                </div>
                {row.count > 1 && <span className="muted tiny">×{row.count}</span>}
              </li>
            ))}
          </ul>
        )}
      </div>
    </section>
  )
}
