import { useEffect, useRef, useState } from 'react'
import { asStatisticRows } from '../game/achievements/progress'
import type { GameDatabase, SkillRow } from '../game/data/types'
import type { PlayerSave } from '../game/save/types'
import { getSkillProgress } from '../game/activity/xp'
import { skillXpProgress } from '../game/activity/xpProgress'
import { skillMenuEntries, type SkillMenuListItem } from '../game/skills/skillActions'
import { CloseButton } from './CloseButton'
import { SkillIcon } from './skillIcons'

function skillXpTooltipText(db: GameDatabase, totalXp: number): string {
  const progress = skillXpProgress(db, totalXp)
  const total = `${progress.totalXp.toLocaleString()} XP`
  if (progress.atCap || progress.nextLevel == null || progress.toNextLevel <= 0) {
    return total
  }
  return `${total}\n${progress.intoLevel.toLocaleString()}/${progress.toNextLevel.toLocaleString()} to Lv ${progress.nextLevel}`
}

interface SkillsViewProps {
  db: GameDatabase
  save: PlayerSave
}

export function SkillsView({ db, save }: SkillsViewProps) {
  const skills = [...db.Skills].sort((a, b) => a['Skill ID'].localeCompare(b['Skill ID']))
  const [heldSkillId, setHeldSkillId] = useState<string | null>(null)
  const [openSkillId, setOpenSkillId] = useState<string | null>(null)
  const statistics = asStatisticRows(db)
  const openSkill = openSkillId
    ? (skills.find((skill) => skill['Skill ID'] === openSkillId) ?? null)
    : null
  const openEntries = openSkillId ? skillMenuEntries(db, openSkillId) : []

  return (
    <section className="skills-view">
      <ul className="skills-grid">
        {skills.map((skill) => {
          const progress = getSkillProgress(save, skill['Skill ID'])
          return (
            <SkillTile
              key={skill['Skill ID']}
              skill={skill}
              level={progress.level}
              xp={progress.xp}
              xpTooltip={skillXpTooltipText(db, progress.xp)}
              showingXp={heldSkillId === skill['Skill ID']}
              onHoldStart={() => setHeldSkillId(skill['Skill ID'])}
              onHoldEnd={() =>
                setHeldSkillId((current) => (current === skill['Skill ID'] ? null : current))
              }
              onOpen={() => setOpenSkillId(skill['Skill ID'])}
            />
          )
        })}
      </ul>

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

      {openSkill && (
        <SkillActionsMenu
          skill={openSkill}
          entries={openEntries}
          onClose={() => setOpenSkillId(null)}
        />
      )}
    </section>
  )
}

function SkillTile({
  skill,
  level,
  xpTooltip,
  showingXp,
  onHoldStart,
  onHoldEnd,
  onOpen,
}: {
  skill: SkillRow
  level: number
  xpTooltip: string
  showingXp: boolean
  onHoldStart: () => void
  onHoldEnd: () => void
  onOpen: () => void
}) {
  const timerRef = useRef<number | null>(null)
  const holdFiredRef = useRef(false)

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
    holdFiredRef.current = false
    clearHoldTimer()
    timerRef.current = window.setTimeout(() => {
      holdFiredRef.current = true
      onHoldStart()
    }, 280)
  }

  function endHold() {
    clearHoldTimer()
    onHoldEnd()
  }

  function handleClick() {
    if (holdFiredRef.current) {
      holdFiredRef.current = false
      return
    }
    onOpen()
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
        onPointerEnter={() => onHoldStart()}
        onClick={handleClick}
        onContextMenu={(event) => event.preventDefault()}
      >
        <SkillIcon internalKey={skill['Internal Key']} title={skill['Display Name']} />
        <strong className="skill-tile-name">{skill['Display Name']}</strong>
        <span className="skill-tile-level">Lv {level}</span>
        {showingXp && (
          <span className="skill-xp-tooltip" role="tooltip">
            {xpTooltip}
          </span>
        )}
      </button>
    </li>
  )
}

function SkillActionsMenu({
  skill,
  entries,
  onClose,
}: {
  skill: SkillRow
  entries: SkillMenuListItem[]
  onClose: () => void
}) {
  return (
    <div className="skill-actions-overlay" role="presentation" onClick={onClose}>
      <section
        className="panel skill-actions-menu"
        role="dialog"
        aria-label={skill['Display Name']}
        onClick={(event) => event.stopPropagation()}
      >
        <div className="skill-actions-head">
          <h2>{skill['Display Name']}</h2>
          <CloseButton onClick={onClose} />
        </div>
        <ul className="skill-actions-list">
          {entries.map((entry) => (
            <li key={entry.id}>
              <span className="skill-action-name">{entry.displayName}</span>
              {entry.level != null && (
                <span className="skill-action-proficiency">{entry.level}</span>
              )}
            </li>
          ))}
        </ul>
      </section>
    </div>
  )
}
