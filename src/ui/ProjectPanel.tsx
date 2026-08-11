import { useEffect, useMemo, useState } from 'react'
import type { ProjectRow } from '../game/data/projectTypes'
import type { GameDatabase } from '../game/data/types'
import { inventoryCount } from '../game/production/recipes'
import { eligibleEnchantmentTargets } from '../game/projects/enchantments'
import { hasProjectKnowledge } from '../game/npcs/knowledge'
import {
  getEnchantment,
  isEnchantmentOutput,
  maxProjectQuantity,
  meetsProjectKnowledge,
  meetsProjectSkills,
  projectInputs,
  projectSkillRequirements,
  projectsForFacility,
  unmetProjectSkillRequirements,
  type SpecialProductionStation,
} from '../game/projects/projects'
import { isSpellItem, spellEffectEnchantmentId, spellTooltipLines } from '../game/spells/spells'
import type { PlayerSave } from '../game/save/types'
import { CloseButton } from './CloseButton'
import { IngredientIconList } from './IngredientIcons'
import { ItemIcon } from './itemIcons'
import { QuantityNumpad } from './QuantityNumpad'

function projectOptionLabel(project: ProjectRow, db: GameDatabase): string {
  const outputId = project['Output Item / Target ID']
  const level = project['Required Skill 1 Level'] ?? 1
  if (isEnchantmentOutput(outputId)) {
    return `${project['Display Name']} (Lv ${level})`
  }
  const itemName =
    db.Items.find((item) => item['Item ID'] === outputId)?.['Display Name'] ??
    project['Display Name']
  return `${project['Display Name']} → ${itemName} (Lv ${level})`
}

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
  const knowledge = hasProjectKnowledge(db, save, station.skillId)
  const initialProjectId =
    projects.find(
      (row) => meetsProjectSkills(save, row) && meetsProjectKnowledge(db, save, row),
    )?.['Project ID'] ??
    projects[0]?.['Project ID'] ??
    ''
  const [projectId, setProjectId] = useState(initialProjectId)
  const project =
    projects.find((row) => row['Project ID'] === projectId) ??
    filteredProjects[0] ??
    null
  const knowledgeMet = project ? meetsProjectKnowledge(db, save, project) : knowledge.ok
  const skillsMet = project ? meetsProjectSkills(save, project) : false
  const unmetSkills = project ? unmetProjectSkillRequirements(db, save, project) : []
  const canCraft = knowledgeMet && skillsMet
  const maxQty = project && canCraft ? maxProjectQuantity(save, project) : 0
  const isEnchant = project ? isEnchantmentOutput(project['Output Item / Target ID']) : false
  const enchantment =
    project && isEnchant ? getEnchantment(db, project['Output Item / Target ID']) : undefined
  const enchantTargets =
    enchantment != null ? eligibleEnchantmentTargets(db, save, enchantment) : []
  const preferredTargetId =
    enchantTargets.find((target) => target.preferred)?.id ?? enchantTargets[0]?.id ?? ''
  const [enchantTargetId, setEnchantTargetId] = useState(preferredTargetId)
  const [quantity, setQuantity] = useState(1)
  const [qtyOpen, setQtyOpen] = useState(false)

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
        </div>
        <CloseButton onClick={onCancel} label="Cancel" />
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
              className="text-input project-select-list"
              value={
                filteredProjects.some((row) => row['Project ID'] === projectId)
                  ? projectId
                  : filteredProjects[0]!['Project ID']
              }
              onChange={(event) => selectProject(event.target.value)}
              size={Math.min(8, Math.max(filteredProjects.length, 3))}
            >
              {filteredProjects.map((row) => {
                const locked =
                  !meetsProjectSkills(save, row) || !meetsProjectKnowledge(db, save, row)
                return (
                  <option key={row['Project ID']} value={row['Project ID']}>
                    {projectOptionLabel(row, db)}
                    {locked ? ' — locked' : ''}
                  </option>
                )
              })}
            </select>
          )}

          {project && (
            <>
              <ProjectDetails db={db} save={save} project={project} />
              {!knowledgeMet && !knowledge.ok && (
                <p className="danger-note">
                  Locked — speak with the {knowledge.npcName} to unlock {station.skillName} projects.
                </p>
              )}
              {knowledgeMet && !skillsMet && (
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
                  <button
                    id="project-qty"
                    type="button"
                    className="text-input qty-open-btn"
                    disabled={!canCraft}
                    onClick={() => setQtyOpen(true)}
                  >
                    {clampedQty.toLocaleString()}
                  </button>
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
                      disabled={!canCraft}
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
                  !canCraft ||
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

      {qtyOpen && project && !isEnchant && (
        <QuantityNumpad
          title={project['Display Name']}
          subtitle="Project quantity"
          details={<p className="muted tiny">Max {maxQty.toLocaleString()}</p>}
          confirmLabel="Set quantity"
          initialValue={clampedQty}
          max={Math.max(1, maxQty)}
          onCancel={() => setQtyOpen(false)}
          onConfirm={(next) => {
            setQuantity(next)
            setQtyOpen(false)
          }}
        />
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
  const spellEffectId =
    outputItem && isSpellItem(db, outputItem['Item ID'])
      ? spellEffectEnchantmentId(db, outputItem['Item ID'])
      : null
  const spellEffect = spellEffectId ? getEnchantment(db, spellEffectId) : undefined
  const skills = projectSkillRequirements(project)
  const outputName =
    outputItem?.['Display Name'] ??
    enchantment?.['Display Name'] ??
    project['Display Name']

  return (
    <div className="recipe-details">
      <div className="recipe-output">
        {outputItem ? <ItemIcon item={outputItem} /> : <span className="item-icon" />}
        <div>
          <strong>
            {outputName} ×{project['Output Quantity']}
          </strong>
          {outputItem && (
            <p className="muted tiny">Item · {outputItem['Item ID']}</p>
          )}
          <p className="muted tiny">
            Instant · {project['XP Reward'].toLocaleString()} XP
            {project['Gold Cost'] > 0 ? ` · ${project['Gold Cost']} gold` : ''}
          </p>
          {(enchantment?.Effect || spellEffect?.Effect) && (
            <p className="muted tiny">{enchantment?.Effect ?? spellEffect?.Effect}</p>
          )}
          {outputItem && isSpellItem(db, outputItem['Item ID']) && (
            <p className="muted tiny">
              {spellTooltipLines(db, outputItem, outputItem['Item ID']).slice(-1)[0]}
            </p>
          )}
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
