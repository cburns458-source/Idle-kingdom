import { useEffect, useRef, useState, type ReactNode } from 'react'
import type { LoadedDatabase } from '../game/data/loadDatabase'
import {
  equipInventoryIndex,
  unequipSlot,
} from '../game/equipment/loadout'
import {
  equipmentForItemId,
  equipmentTooltipStatLines,
} from '../game/equipment/tooltips'
import { withRecalculatedVitals } from '../game/equipment/vitals'
import { playerDamageRange, playerDamageReduction, playerMaxHp } from '../game/combat/stats'
import { destroyInventoryIndexes } from '../game/inventory/destroy'
import { enchantmentTooltipLines } from '../game/projects/enchantments'
import type { PlayerSave } from '../game/save/types'
import {
  activeSpellSlotId,
  activeSpellSlotRemainingMs,
  isSpellItem,
  isSpellSlotId,
  spellTooltipLines,
} from '../game/spells/spells'
import { ItemIcon, SlotGlyph } from './itemIcons'

type ItemsSubTab = 'items' | 'equipment'

/** Paper-doll order: 4 columns × 4 rows (spells in the right column). */
const EQUIPMENT_GRID_ORDER = [
  'SLOT-0008', // Neck
  'SLOT-0003', // Helmet
  'SLOT-0010', // Back
  'SLOT-0013', // Spell 1
  'SLOT-0001', // Weapon / Tool
  'SLOT-0004', // Chest
  'SLOT-0002', // Off-hand / Shield
  'SLOT-0014', // Spell 2
  'SLOT-0009', // Ring
  'SLOT-0005', // Legs
  'SLOT-0007', // Gloves
  'SLOT-0015', // Spell 3
  'SLOT-0011', // Food
  'SLOT-0006', // Boots
  'SLOT-0012', // Potion
  'SLOT-0016', // Spell 4
] as const

interface InventoryViewProps {
  save: PlayerSave
  database: LoadedDatabase
  onChangeSave: (save: PlayerSave) => void
}

export function InventoryView({ save, database, onChangeSave }: InventoryViewProps) {
  const [subTab, setSubTab] = useState<ItemsSubTab>('items')
  const [message, setMessage] = useState<string | null>(null)
  const [heldTip, setHeldTip] = useState<string | null>(null)
  const [destroyMode, setDestroyMode] = useState(false)
  const [selectedIndexes, setSelectedIndexes] = useState<Set<number>>(() => new Set())
  const [confirmDestroy, setConfirmDestroy] = useState(false)
  const db = database.launch
  const damage = playerDamageRange(db, save)
  const maxHp = playerMaxHp(db, save)
  const dr = playerDamageReduction(db, save)
  const selectedCount = selectedIndexes.size
  const activeSpellSlot = activeSpellSlotId(db)
  const spellCycleSecondsLeft = Math.ceil(activeSpellSlotRemainingMs(db) / 1000)

  function commit(next: PlayerSave) {
    onChangeSave(withRecalculatedVitals(db, next))
  }

  function exitDestroyMode() {
    setDestroyMode(false)
    setSelectedIndexes(new Set())
    setConfirmDestroy(false)
    setHeldTip(null)
  }

  function equipAt(index: number) {
    const result = equipInventoryIndex(db, save, index)
    if (!result.ok) {
      setMessage(result.reason)
      return
    }
    setMessage(null)
    commit(result.save)
  }

  function unequip(slotId: string) {
    setMessage(null)
    commit(unequipSlot(save, slotId))
  }

  function toggleDestroySelection(index: number) {
    setSelectedIndexes((current) => {
      const next = new Set(current)
      if (next.has(index)) next.delete(index)
      else next.add(index)
      return next
    })
  }

  function confirmDestroySelected() {
    if (selectedCount === 0) return
    const next = destroyInventoryIndexes(save, selectedIndexes)
    commit(next)
    setMessage(
      selectedCount === 1 ? 'Destroyed 1 item stack.' : `Destroyed ${selectedCount} item stacks.`,
    )
    exitDestroyMode()
  }

  return (
    <section className="inventory-view">
      <section className="panel inventory-head">
        <h1>Items</h1>
        <dl className="inventory-stat-strip">
          <div>
            <dt>Damage</dt>
            <dd>
              {damage.min}–{damage.max}
            </dd>
          </div>
          <div>
            <dt>Health</dt>
            <dd>
              {save.currentHp}/{maxHp}
            </dd>
          </div>
          <div>
            <dt>DR</dt>
            <dd>{dr}</dd>
          </div>
        </dl>
        <div className="inventory-subnav" role="tablist" aria-label="Items sections">
          <button
            type="button"
            role="tab"
            aria-selected={subTab === 'items'}
            className={subTab === 'items' ? 'inventory-subnav-btn active' : 'inventory-subnav-btn'}
            onClick={() => {
              setSubTab('items')
              setHeldTip(null)
            }}
          >
            Items
          </button>
          <button
            type="button"
            role="tab"
            aria-selected={subTab === 'equipment'}
            className={
              subTab === 'equipment' ? 'inventory-subnav-btn active' : 'inventory-subnav-btn'
            }
            onClick={() => {
              setSubTab('equipment')
              exitDestroyMode()
              setHeldTip(null)
            }}
          >
            Equipment
          </button>
        </div>
        {message && <p className="danger-note">{message}</p>}
      </section>

      {subTab === 'items' ? (
        <section className="panel inventory-bag-panel">
          <div className="inventory-bag-actions">
            {!destroyMode ? (
              <button
                type="button"
                className="btn secondary"
                disabled={save.inventory.length === 0}
                onClick={() => {
                  setDestroyMode(true)
                  setSelectedIndexes(new Set())
                  setConfirmDestroy(false)
                  setMessage(null)
                  setHeldTip(null)
                }}
              >
                Destroy items
              </button>
            ) : (
              <>
                <button
                  type="button"
                  className="btn secondary"
                  onClick={exitDestroyMode}
                >
                  Cancel
                </button>
                <button
                  type="button"
                  className="btn danger"
                  disabled={selectedCount === 0}
                  onClick={() => setConfirmDestroy(true)}
                >
                  Destroy selected{selectedCount > 0 ? ` (${selectedCount})` : ''}
                </button>
              </>
            )}
          </div>

          {save.inventory.length === 0 ? (
            <p className="lead">No items yet. Fight or gather to fill this grid.</p>
          ) : (
            <ul className="item-bag-grid">
              {save.inventory.map((stack, index) => {
                const item = database.launchIndexes.itemsById.get(stack.itemId)
                const tipId = `bag:${index}:${stack.itemId}:${stack.enchantmentId ?? 'plain'}`
                const equipment = equipmentForItemId(db, stack.itemId)
                const enchantLines = enchantmentTooltipLines(db, stack)
                const spellLines = isSpellItem(db, stack.itemId)
                  ? spellTooltipLines(db, item, stack.itemId)
                  : []
                const tipText = [
                  item?.['Display Name'] ?? stack.itemId,
                  ...equipmentTooltipStatLines(equipment),
                  ...enchantLines,
                  ...spellLines,
                ].join('\n')
                const enchanted = Boolean(stack.enchantmentId)
                const selected = selectedIndexes.has(index)
                return (
                  <li key={tipId}>
                    <HoldTile
                      className={[
                        'bag-item-tile',
                        enchanted ? 'enchanted' : '',
                        destroyMode && selected ? 'selected-destroy' : '',
                      ]
                        .filter(Boolean)
                        .join(' ')}
                      ariaLabel={
                        destroyMode
                          ? `${selected ? 'Deselect' : 'Select'} ${item?.['Display Name'] ?? stack.itemId}`
                          : tipText
                      }
                      showingTip={!destroyMode && heldTip === tipId}
                      tipText={tipText}
                      onHoldStart={() => {
                        if (!destroyMode) setHeldTip(tipId)
                      }}
                      onHoldEnd={() =>
                        setHeldTip((current) => (current === tipId ? null : current))
                      }
                      onActivate={() => {
                        if (destroyMode) {
                          toggleDestroySelection(index)
                          return
                        }
                        if (equipment?.['Slot ID']) equipAt(index)
                      }}
                    >
                      <ItemIcon item={item} className="bag-item-icon" />
                      {enchanted && <span className="item-enchant-star" aria-hidden>★</span>}
                      {isSpellItem(db, stack.itemId) && (
                        <span className="bag-item-name-tag">
                          {item?.['Display Name'] ?? 'Spell'}
                        </span>
                      )}
                      {!enchanted && stack.quantity > 1 && (
                        <span className="bag-item-qty">{stack.quantity}</span>
                      )}
                      {destroyMode && selected && (
                        <span className="bag-item-selected-mark" aria-hidden>
                          ✓
                        </span>
                      )}
                    </HoldTile>
                  </li>
                )
              })}
            </ul>
          )}
          <p className="muted tiny">
            {destroyMode
              ? 'Tap items to select them, then confirm to destroy the selected stacks.'
              : 'Hold an item for its name, combat stats, and enchantment. Tap gear to equip. Enchanted items do not stack.'}
          </p>
        </section>
      ) : (
        <section className="panel inventory-equipment-panel">
          <ul className="equipment-paper-grid">
            {EQUIPMENT_GRID_ORDER.map((slotId) => {
              const slot = db.EquipmentSlots.find((entry) => entry['Slot ID'] === slotId)
              const stack = save.equipment.slots[slotId]
              const item = stack
                ? database.launchIndexes.itemsById.get(stack.itemId)
                : undefined
              const tipId = `slot:${slotId}`
              const equipment = stack ? equipmentForItemId(db, stack.itemId) : undefined
              const enchantLines = enchantmentTooltipLines(db, stack)
              const spellLines = stack && isSpellItem(db, stack.itemId)
                ? spellTooltipLines(db, item, stack.itemId)
                : []
              const isActiveSpell = isSpellSlotId(slotId) && slotId === activeSpellSlot
              const tipText = stack
                ? [
                    `${item?.['Display Name'] ?? stack.itemId}${
                      stack.quantity > 1 ? ` ×${stack.quantity}` : ''
                    }`,
                    ...equipmentTooltipStatLines(equipment),
                    ...enchantLines,
                    ...spellLines,
                    isActiveSpell ? 'Active spell slot' : null,
                  ]
                    .filter(Boolean)
                    .join('\n')
                : [
                    slot?.['Display Name'] ?? slotId,
                    isSpellSlotId(slotId) ? 'Equip a spell from your bag.' : null,
                    isActiveSpell ? 'Active spell slot' : null,
                  ]
                    .filter(Boolean)
                    .join('\n')
              const enchanted = Boolean(stack?.enchantmentId)

              return (
                <li key={slotId}>
                  <HoldTile
                    className={[
                      stack ? 'equip-slot-tile filled' : 'equip-slot-tile empty',
                      enchanted ? 'enchanted' : '',
                      isActiveSpell ? 'spell-slot-active' : '',
                    ]
                      .filter(Boolean)
                      .join(' ')}
                    ariaLabel={tipText}
                    showingTip={heldTip === tipId}
                    tipText={tipText}
                    onHoldStart={() => setHeldTip(tipId)}
                    onHoldEnd={() => setHeldTip((current) => (current === tipId ? null : current))}
                    onActivate={() => {
                      if (stack) unequip(slotId)
                    }}
                  >
                    {stack ? <ItemIcon item={item} /> : <SlotGlyph slotId={slotId} />}
                    {enchanted && <span className="item-enchant-star" aria-hidden>★</span>}
                    {stack && !enchanted && stack.quantity > 1 && (
                      <span className="bag-item-qty">{stack.quantity}</span>
                    )}
                  </HoldTile>
                </li>
              )
            })}
          </ul>
          <p className="muted tiny">
            Spell slots cycle every hour. Active slot changes in {spellCycleSecondsLeft}s.
          </p>
          <p className="muted tiny">
            Hold a slot for its name, combat stats, and enchantment. Tap equipped gear to unequip.
          </p>
        </section>
      )}

      {confirmDestroy ? (
        <div
          className="destroy-confirm-overlay"
          role="dialog"
          aria-modal="true"
          aria-labelledby="destroy-confirm-title"
        >
          <div className="panel destroy-confirm-card">
            <h2 id="destroy-confirm-title">Destroy items?</h2>
            <p className="lead">
              Permanently remove {selectedCount} selected stack
              {selectedCount === 1 ? '' : 's'} from your bag. Equipped items are not affected.
            </p>
            <div className="button-row">
              <button type="button" className="btn secondary" onClick={() => setConfirmDestroy(false)}>
                Keep items
              </button>
              <button type="button" className="btn danger" onClick={confirmDestroySelected}>
                Confirm destroy
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </section>
  )
}

function HoldTile({
  className,
  ariaLabel,
  showingTip,
  tipText,
  onHoldStart,
  onHoldEnd,
  onActivate,
  children,
}: {
  className: string
  ariaLabel: string
  showingTip: boolean
  tipText: string
  onHoldStart: () => void
  onHoldEnd: () => void
  onActivate: () => void
  children: ReactNode
}) {
  const timerRef = useRef<number | null>(null)
  const heldRef = useRef(false)

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
    heldRef.current = false
    clearHoldTimer()
    timerRef.current = window.setTimeout(() => {
      heldRef.current = true
      onHoldStart()
    }, 280)
  }

  function endHold() {
    clearHoldTimer()
    onHoldEnd()
  }

  return (
    <button
      type="button"
      className={showingTip ? `${className} showing-tip` : className}
      aria-label={ariaLabel}
      onPointerDown={beginHold}
      onPointerUp={(event) => {
        const wasHeld = heldRef.current
        endHold()
        if (!wasHeld && event.button === 0) onActivate()
      }}
      onPointerLeave={endHold}
      onPointerCancel={endHold}
      onContextMenu={(event) => event.preventDefault()}
    >
      {children}
      {showingTip && (
        <span className="item-name-tooltip" role="tooltip">
          {tipText}
        </span>
      )}
    </button>
  )
}
