import type { GameDatabase } from '../game/data/types'
import type { PlayerSave } from '../game/save/types'
import { getSkillProgress } from '../game/activity/xp'
import { totalLevel, totalSkillXp } from '../game/skills/totals'
import { SkillIcon } from './skillIcons'

interface SkillsViewProps {
  db: GameDatabase
  save: PlayerSave
}

export function SkillsView({ db, save }: SkillsViewProps) {
  const skills = [...db.Skills].sort((a, b) => a['Skill ID'].localeCompare(b['Skill ID']))
  const overallLevel = totalLevel(save)
  const overallXp = totalSkillXp(save)

  return (
    <section className="skills-view">
      <section className="panel skills-summary">
        <h1>Skills</h1>
        <dl className="skills-summary-stats">
          <div>
            <dt>Total Level</dt>
            <dd>{overallLevel.toLocaleString()}</dd>
          </div>
          <div>
            <dt>Total XP</dt>
            <dd>{overallXp.toLocaleString()}</dd>
          </div>
        </dl>
      </section>

      <ul className="skills-list">
        {skills.map((skill) => {
          const progress = getSkillProgress(save, skill['Skill ID'])
          return (
            <li key={skill['Skill ID']} className="skill-row">
              <SkillIcon internalKey={skill['Internal Key']} title={skill['Display Name']} />
              <div className="skill-row-text">
                <div className="skill-row-top">
                  <strong>{skill['Display Name']}</strong>
                  <span className="skill-level">Lv {progress.level}</span>
                </div>
                <p className="skill-xp">{progress.xp.toLocaleString()} XP</p>
                <p className="muted tiny">{skill.Category}</p>
              </div>
            </li>
          )
        })}
      </ul>
    </section>
  )
}
