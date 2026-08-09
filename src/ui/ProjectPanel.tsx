import { useEffect, useMemo, useState } from 'react'
import type { ProjectRow } from '../game/data/projectTypes'
import type { GameDatabase } from '../game/data/types'
import { inventoryCount } from '../game/production/recipes'
import { eligibleEnchantmentTargets } from '../game/projects/enchantments'
import {
  getEnchantment,
  isEnchantmentOutput,
  maxProjectQuantity,
  meetsProjectSkills,
  projectInputs,
  projectSkillRequirements,
  projectsForFacility,
  unmetProjectSkillRequirements,
  type SpecialProductionStation,
} from '../game/projects/projects'
import type { PlayerSave } from '../game/save/types'
import { IngredientIconList } from './IngredientIcons'
import { ItemIcon } from './itemIcons'

interface ProjectPickerProps {
  db: GameDatabase
  save: PlayerSave
  station: SpecialProductionStation
  onCancel: () => void
  onConfirm: (projectId: string, quantity: number, enchantTargetId: string | null) => void
}

function projectMatchesQuery(project: ProjectRow, query: string, db: GameDatabase): boolean {
  const needle = query.trim().toLowerCase()
  if (!needle) return true
  if (project['Display Name'].toLowerCase().includes(needle)) return true
  if (project['Internal Key'].toLowerCase().includes(needle)) return true
  const outputId = project['Output Item / Target ID']
  const itemName = db.Items.find((item) => item['Item ID'] === outputId)?.['Display Name']
  if (itemName?.toLowerCase().includes(needle)) return true
  const enchantName = db.Enchantments.find((row) => row['Enchantment ID'] === outputId)?.[
    'Display Name'
  ]
  if (enchantName?.toLowerCase().includes(needle)) return true
  return false
}

export function ProjectPicker({
  db,
  save,
  station,
  onCancel,
  onConfirm,
}: ProjectPickerProps) {
  const projects = useMemo(
    () => projectsForFacility(db, station.facility['Facility ID'], station.skillId),
    [db, station],
  )
  const [search, setSearch] = useState('')
  const filteredProjects = useMemo(
    () => projects.filter((project) => projectMatchesQuery(project, search, db)),
    [projects, search, db],
  )
  const initialProjectId =
    projects.find((row) => meetsProjectSkills(save, row))?.['Project ID'] ??
    projects[0]?.['Project ID'] ??
    ''
  const [projectId, setProjectId] = useState(initialProjectId)
  const project =
    projects.find((row) => row['Project ID'] === projectId) ??
    filteredProjects[0] ??
    null
  const skillsMet = project ? meetsProjectSkills(save, project) : false
  const unmetSkills = project ? unmetProjectSkillRequirements(db, save, project) : []
  const maxQty = project && skillsMet ? maxProjectQuantity(save, project) : 0
  const isEnchant = project ? isEnchantmentOutput(project['Output Item / Target ID']) : false
  const enchantment =
    project && isEnchant ? getEnchantment(db, project['Output Item / Target ID']) : undefined
  const enchantTargets =
    enchantment != null ? eligibleEnchantmentTargets(db, save, enchantment) : []
  const preferredTargetId =
    enchantTargets.find((target) => target.preferred)?.id ?? enchantTargets[0]?.id ?? ''
  const [enchantTargetId, setEnchantTargetId] = useState(preferredTargetId)
  const [quantity, setQuantity] = useState(1)

  useEffect(() => {
    if (filteredProjects.length === 0) return
    if (!filteredProjects.some((row) => row['Project ID'] === projectId)) {
      setProjectId(filteredProjects[0]!['Project ID'])
      setQuantity(1)
      setEnchantTargetId('')
    }
  }, [filteredProjects, projectId])

  useEffect(() => {
    if (enchantTargets.length === 0) {
      setEnchantTargetId('')
      return
    }
    if (!enchantTargets.some((target) => target.id === enchantTargetId)) {
      setEnchantTargetId(preferredTargetId)
    }
  }, [enchantTargets, enchantTargetId, preferredTargetId])

  const clampedQty = isEnchant
    ? 1
    : Math.min(Math.max(1, quantity), Math.max(1, maxQty || 1))

  function selectProject(nextId: string) {
    setProjectId(nextId)
    setQuantity(1)
    setEnchantTargetId('')
  }

  return (
    <section className="panel production-picker glass-panel">
      <div className="activity-panel-head">
        <div>
          <h2>{station.label}</h2>
          <p className="muted">
            {station.facility['Display Name']} · instant Special Production
          </p>
        </div>
        <button type="button" className="btn secondary" onClick={onCancel}>
          Cancel
        </button>
      </div>

      {projects.length === 0 ? (
        <p className="lead">No projects are defined for this station yet.</p>
      ) : (
        <>
          <label className="field-label" htmlFor="project-search">
            Search projects
          </label>
          <input
            id="project-search"
            className="text-input"
            type="search"
            enterKeyHint="search"
            placeholder="Type a name…"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            autoComplete="off"
          />

          <label className="field-label" htmlFor="project-select">
            Project
            {search.trim()
              ? ` (${filteredProjects.length} of ${projects.length})`
              : ` (${projects.length})`}
          </label>
          {filteredProjects.length === 0 ? (
            <p className="muted tiny">No projects match that search.</p>
          ) : (
            <select
              id="project-select"
              className="text-input"
              value={
                filteredProjects.some((row) => row['Project ID'] === projectId)
                  ? projectId
                  : filteredProjects[0]!['Project ID']
              }
              onChange={(event) => selectProject(event.target.value)}
              size={Math.min(6, Math.max(3, filteredProjects.length))}
            >
              {filteredProjects.map((row) => {
                const locked = !meetsProjectSkills(save, row)
                return (
                  <option key={row['Project ID']} value={row['Project ID']}>
                    {row['Display Name']} (Lv {row['Required Skill 1 Level'] ?? 1})
                    {locked ? ' — locked' : ''}
                  </option>
                )
              })}
            </select>
          )}

          {project && (
            <>
              <ProjectDetails db={db} save={save} project={project} />
              {!skillsMet && (
                <p className="danger-note">
                  Locked — needs{' '}
                  {unmetSkills
                    .map((requirement) => `${requirement.skillName} ${requirement.level}`)
                    .join(', ')}
                  .
                </p>
              )}
              {!isEnchant && (
                <>
                  <label className="field-label" htmlFor="project-qty">
                    Quantity (max {maxQty})
                  </label>
                  <input
                    id="project-qty"
                    className="text-input"
                    type="number"
                    min={1}
                    max={Math.max(1, maxQty)}
                    value={clampedQty}
                    disabled={!skillsMet}
                    onChange={(event) => setQuantity(Number(event.target.value) || 1)}
                  />
                </>
              )}
              {isEnchant && (
                <>
                  <label className="field-label" htmlFor="enchant-target">
                    Item to enchant
                  </label>
                  {enchantTargets.length === 0 ? (
                    <p className="danger-note">
                      Equip or keep a valid unenchanted item in inventory.
                    </p>
                  ) : (
                    <select
                      id="enchant-target"
                      className="text-input"
                      value={enchantTargetId || preferredTargetId}
                      disabled={!skillsMet}
                      onChange={(event) => setEnchantTargetId(event.target.value)}
                    >
                      {enchantTargets.map((target) => (
                        <option key={target.id} value={target.id}>
                          {target.label}
                        </option>
                      ))}
                    </select>
                  )}
                </>
              )}
              <button
                type="button"
                className="btn primary"
                disabled={
                  !skillsMet ||
                  maxQty <= 0 ||
                  (isEnchant && enchantTargets.length === 0)
                }
                onClick={() =>
                  onConfirm(
                    project['Project ID'],
                    clampedQty,
                    isEnchant ? enchantTargetId || preferredTargetId || null : null,
                  )
                }
              >
                Complete project
              </button>
            </>
          )}
        </>
      )}
    </section>
  )
}

function ProjectDetails({
  db,
  save,
  project,
}: {
  db: GameDatabase
  save: PlayerSave
  project: ProjectRow
}) {
  const inputs = projectInputs(project)
  const outputId = project['Output Item / Target ID']
  const enchantment = isEnchantmentOutput(outputId) ? getEnchantment(db, outputId) : undefined
  const outputItem = !enchantment
    ? db.Items.find((item) => item['Item ID'] === outputId)
    : undefined
  const skills = projectSkillRequirements(project)

  return (
    <div className="recipe-details">
      <div className="recipe-output">
        {outputItem ? <ItemIcon item={outputItem} /> : <span className="item-icon" />}
        <div>
          <strong>
            {enchantment?.['Display Name'] ??
              outputItem?.['Display Name'] ??
              project['Display Name']}{' '}
            ×{project['Output Quantity']}
          </strong>
          <p className="muted tiny">
            Instant · {project['XP Reward'].toLocaleString()} XP
            {project['Gold Cost'] > 0 ? ` · ${project['Gold Cost']} gold` : ''}
          </p>
          {enchantment?.Effect && <p className="muted tiny">{enchantment.Effect}</p>}
        </div>
      </div>
      {skills.length > 0 && (
        <p className="muted tiny project-skill-reqs">
          {skills
            .map((requirement) => {
              const skill = db.Skills.find((row) => row['Skill ID'] === requirement.skillId)
              return `${skill?.['Display Name'] ?? requirement.skillId} ${requirement.level}`
            })
            .join(' · ')}
        </p>
      )}
      <IngredientIconList
        ingredients={inputs.map((input) => ({
          itemId: input.itemId,
          item: db.Items.find((row) => row['Item ID'] === input.itemId),
          need: input.quantity,
          owned: inventoryCount(save, input.itemId),
        }))}
      />
      {project['Gold Cost'] > 0 && (
        <p className={save.gold < project['Gold Cost'] ? 'danger-note tiny' : 'muted tiny'}>
          Gold ×{project['Gold Cost']} (have {save.gold})
        </p>
      )}
    </div>
  )
}
