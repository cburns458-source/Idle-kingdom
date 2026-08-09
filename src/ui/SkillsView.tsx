import { useEffect, useRef, useState } from 'react'
import {
  asAchievementRows,
  asStatisticRows,
} from '../game/achievements/progress'
import type { GameDatabase, SkillRow } from '../game/data/types'
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
  const [heldSkillId, setHeldSkillId] = useState<string | null>(null)
  const statistics = asStatisticRows(db)
  const achievements = asAchievementRows(db)

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
        <p className="muted tiny">Hold a skill to see its total XP.</p>
      </section>

      <section className="panel skills-summary">
        <h2>Statistics</h2>
        <dl className="skills-summary-stats">
          {statistics.map((stat) => (
            <div key={stat['Statistic ID']}>
              <dt>{stat['Display Name']}</dt>
              <dd>{Number(save.statistics.values[stat['Internal Key']] ?? 0).toLocaleString()}</dd>
            </div>
          ))}
        </dl>
      </section>

      <section className="panel skills-summary">
        <h2>Achievements</h2>
        <ul className="achievement-list">
          {achievements.map((achievement) => {
            const unlocked = save.achievements.some(
              (row) => row.achievementId === achievement['Achievement ID'] && row.unlocked,
            )
            const skillName =
              db.Skills.find((skill) => skill['Skill ID'] === achievement['Target Skill ID'])?.[
                'Display Name'
              ] ?? 'Skill'
            return (
              <li key={achievement['Achievement ID']} className={unlocked ? 'unlocked' : ''}>
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
      </section>

      <ul className="skills-grid">
        {skills.map((skill) => {
          const progress = getSkillProgress(save, skill['Skill ID'])
          return (
            <SkillTile
              key={skill['Skill ID']}
              skill={skill}
              level={progress.level}
              xp={progress.xp}
              showingXp={heldSkillId === skill['Skill ID']}
              onHoldStart={() => setHeldSkillId(skill['Skill ID'])}
              onHoldEnd={() =>
                setHeldSkillId((current) => (current === skill['Skill ID'] ? null : current))
              }
            />
          )
        })}
      </ul>
    </section>
  )
}

function SkillTile({
  skill,
  level,
  xp,
  showingXp,
  onHoldStart,
  onHoldEnd,
}: {
  skill: SkillRow
  level: number
  xp: number
  showingXp: boolean
  onHoldStart: () => void
  onHoldEnd: () => void
}) {
  const timerRef = useRef<number | null>(null)

  useEffect(() => {
    return () => {
      if (timerRef.current != null) window.clearTimeout(timerRef.current)
    }
  }, [])

  function clearHoldTimer() {
    if (timerRef.current != null) {
      window.clearTimeout(timerRef.current)
      timerRef.current = null
    }
  }

  function beginHold() {
    clearHoldTimer()
    timerRef.current = window.setTimeout(() => {
      onHoldStart()
    }, 280)
  }

  function endHold() {
    clearHoldTimer()
    onHoldEnd()
  }

  return (
    <li>
      <button
        type="button"
        className={showingXp ? 'skill-tile showing-xp' : 'skill-tile'}
        aria-label={`${skill['Display Name']}, level ${level}`}
        onPointerDown={beginHold}
        onPointerUp={endHold}
        onPointerLeave={endHold}
        onPointerCancel={endHold}
        onContextMenu={(event) => event.preventDefault()}
      >
        <SkillIcon internalKey={skill['Internal Key']} title={skill['Display Name']} />
        <strong className="skill-tile-name">{skill['Display Name']}</strong>
        <span className="skill-tile-level">Lv {level}</span>
        {showingXp && (
          <span className="skill-xp-tooltip" role="tooltip">
            {xp.toLocaleString()} XP
          </span>
        )}
      </button>
    </li>
  )
}
