import { useEffect, useMemo, useState } from 'react'
import type { GameDatabase } from '../game/data/types'
import {
  defaultProjectId,
  projectDetail,
  projectMenuList,
  type ProjectDetail,
} from '../game/projects/menu'
import type { SpecialProductionStation } from '../game/projects/projects'
import type { PlayerSave } from '../game/save/types'
import { CloseButton } from './CloseButton'
import { IngredientIconList } from './IngredientIcons'
import { ItemIcon } from './itemIcons'
import { QuantityNumpad } from './QuantityNumpad'

interface ProjectPickerProps {
  db: GameDatabase
  save: PlayerSave
  station: SpecialProductionStation
  onCancel: () => void
  onConfirm: (projectId: string, quantity: number, enchantTargetId: string | null) => void
}

export function ProjectPicker({
  db,
  save,
  station,
  onCancel,
  onConfirm,
}: ProjectPickerProps) {
  const facilityId = station.facility['Facility ID']
  const [search, setSearch] = useState('')
  const all = useMemo(
    () => projectMenuList(db, save, facilityId, station.skillId),
    [db, save, facilityId, station.skillId],
  )
  const listed = useMemo(
    () => projectMenuList(db, save, facilityId, station.skillId, search),
    [db, save, facilityId, station.skillId, search],
  )
  const [projectId, setProjectId] = useState(
    () => defaultProjectId(db, save, facilityId, station.skillId) ?? '',
  )
  const [quantity, setQuantity] = useState(1)
  const [enchantTargetId, setEnchantTargetId] = useState('')
  const [qtyOpen, setQtyOpen] = useState(false)

  const selectedId = listed.some((row) => row.projectId === projectId)
    ? projectId
    : (listed[0]?.projectId ?? '')
  const detail = selectedId ? projectDetail(db, save, selectedId) : null
  const preferredTargetId =
    detail?.enchantTargets.find((target) => target.preferred)?.id ??
    detail?.enchantTargets[0]?.id ??
    ''

  useEffect(() => {
    if (!detail) return
    if (!detail.enchantTargets.some((target) => target.id === enchantTargetId)) {
      setEnchantTargetId(preferredTargetId)
    }
  }, [detail, enchantTargetId, preferredTargetId])

  const canCraft = detail?.lockedReason === null
  const maxQty = detail?.maxQuantity ?? 0
  const clampedQty = detail?.isEnchantment
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

      {all.length === 0 ? (
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
            {search.trim() ? ` (${listed.length} of ${all.length})` : ` (${all.length})`}
          </label>
          {listed.length === 0 ? (
            <p className="muted tiny">No projects match that search.</p>
          ) : (
            <select
              id="project-select"
              className="text-input project-select-list"
              value={selectedId}
              onChange={(event) => selectProject(event.target.value)}
              size={Math.min(8, Math.max(listed.length, 3))}
            >
              {listed.map((row) => (
                <option key={row.projectId} value={row.projectId}>
                  {row.label}
                  {row.locked ? ' — locked' : ''}
                </option>
              ))}
            </select>
          )}

          {detail && (
            <>
              <ProjectDetails db={db} detail={detail} />
              {detail.lockedReason && <p className="danger-note">{detail.lockedReason}</p>}
              {!detail.isEnchantment && (
                <>
                  <label className="field-label" htmlFor="project-qty">
                    Quantity (max {maxQty})
                  </label>
                  <div className="production-qty-row">
                    <button
                      id="project-qty"
                      type="button"
                      className="text-input qty-open-btn"
                      disabled={!canCraft}
                      onClick={() => setQtyOpen(true)}
                    >
                      {clampedQty.toLocaleString()}
                    </button>
                    <button
                      type="button"
                      className="btn primary"
                      disabled={!canCraft || maxQty <= 0}
                      onClick={() => onConfirm(detail.projectId, clampedQty, null)}
                    >
                      Complete project
                    </button>
                  </div>
                </>
              )}
              {detail.isEnchantment && (
                <>
                  <label className="field-label" htmlFor="enchant-target">
                    Item to enchant
                  </label>
                  {detail.enchantTargets.length === 0 ? (
                    <p className="danger-note">
                      Equip or keep a valid unenchanted item in inventory.
                    </p>
                  ) : (
                    <div className="production-qty-row">
                      <select
                        id="enchant-target"
                        className="text-input"
                        value={enchantTargetId || preferredTargetId}
                        disabled={!canCraft}
                        onChange={(event) => setEnchantTargetId(event.target.value)}
                      >
                        {detail.enchantTargets.map((target) => (
                          <option key={target.id} value={target.id}>
                            {target.label}
                          </option>
                        ))}
                      </select>
                      <button
                        type="button"
                        className="btn primary"
                        disabled={!canCraft}
                        onClick={() =>
                          onConfirm(
                            detail.projectId,
                            1,
                            enchantTargetId || preferredTargetId || null,
                          )
                        }
                      >
                        Complete project
                      </button>
                    </div>
                  )}
                </>
              )}
            </>
          )}
        </>
      )}

      {qtyOpen && detail && !detail.isEnchantment && (
        <QuantityNumpad
          title={detail.name}
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

function ProjectDetails({ db, detail }: { db: GameDatabase; detail: ProjectDetail }) {
  const outputItem = detail.outputItemId
    ? db.Items.find((item) => item['Item ID'] === detail.outputItemId)
    : undefined

  return (
    <div className="recipe-details">
      <div className="recipe-output">
        {outputItem ? <ItemIcon item={outputItem} /> : <span className="item-icon" />}
        <div>
          <strong>
            {detail.outputName} ×{detail.outputQuantity}
          </strong>
          {detail.outputItemId && <p className="muted tiny">Item · {detail.outputItemId}</p>}
          <p className="muted tiny">{detail.summaryLine}</p>
          {detail.effectLine && <p className="muted tiny">{detail.effectLine}</p>}
        </div>
      </div>
      {detail.skillLine && <p className="muted tiny project-skill-reqs">{detail.skillLine}</p>}
      <IngredientIconList
        ingredients={detail.ingredients.map((line) => ({
          itemId: line.itemId,
          item: db.Items.find((row) => row['Item ID'] === line.itemId),
          need: line.need,
          owned: line.owned,
        }))}
      />
      {detail.goldCost > 0 && (
        <p className={detail.goldOwned < detail.goldCost ? 'danger-note tiny' : 'muted tiny'}>
          Gold ×{detail.goldCost} (have {detail.goldOwned})
        </p>
      )}
    </div>
  )
}
