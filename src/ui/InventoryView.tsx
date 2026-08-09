import { useEffect, useRef, useState, type ReactNode } from 'react'
import type { LoadedDatabase } from '../game/data/loadDatabase'
import {
  equipItemFromInventory,
  unequipSlot,
} from '../game/equipment/loadout'
import { withRecalculatedVitals } from '../game/equipment/vitals'
import { playerDamageRange, playerDamageReduction, playerMaxHp } from '../game/combat/stats'
import type { PlayerSave } from '../game/save/types'
import { ItemIcon, SlotGlyph } from './itemIcons'

type ItemsSubTab = 'items' | 'equipment'

/** Paper-doll order: 3 columns × 4 rows. */
const EQUIPMENT_GRID_ORDER = [
  'SLOT-0008', // Neck
  'SLOT-0003', // Helmet
  'SLOT-0010', // Back
  'SLOT-0001', // Weapon / Tool
  'SLOT-0004', // Chest
  'SLOT-0002', // Off-hand / Shield
  'SLOT-0009', // Ring
  'SLOT-0005', // Legs
  'SLOT-0007', // Gloves
  'SLOT-0011', // Food
  'SLOT-0006', // Boots
  'SLOT-0012', // Potion
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
  const db = database.launch
  const damage = playerDamageRange(db, save)
  const maxHp = playerMaxHp(db, save)
  const dr = playerDamageReduction(db, save)

  function commit(next: PlayerSave) {
    onChangeSave(withRecalculatedVitals(db, next))
  }

  function equipItem(itemId: string) {
    const result = equipItemFromInventory(db, save, itemId)
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
          {save.inventory.length === 0 ? (
            <p className="lead">No items yet. Fight or gather to fill this grid.</p>
          ) : (
            <ul className="item-bag-grid">
              {save.inventory.map((stack) => {
                const item = database.launchIndexes.itemsById.get(stack.itemId)
                const tipId = `bag:${stack.itemId}`
                const equipment = db.Equipment.find((row) => row['Item ID'] === stack.itemId)
                return (
                  <li key={stack.itemId}>
                    <HoldTile
                      className="bag-item-tile"
                      ariaLabel={`${item?.['Display Name'] ?? stack.itemId}, quantity ${stack.quantity}`}
                      showingTip={heldTip === tipId}
                      tipText={item?.['Display Name'] ?? stack.itemId}
                      onHoldStart={() => setHeldTip(tipId)}
                      onHoldEnd={() =>
                        setHeldTip((current) => (current === tipId ? null : current))
                      }
                      onActivate={() => {
                        if (equipment?.['Slot ID']) equipItem(stack.itemId)
                      }}
                    >
                      <ItemIcon item={item} className="bag-item-icon" />
                      <span className="bag-item-qty">{stack.quantity}</span>
                    </HoldTile>
                  </li>
                )
              })}
            </ul>
          )}
          <p className="muted tiny">Hold an item to see its name. Tap gear to equip.</p>
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
              const tipText = stack
                ? `${item?.['Display Name'] ?? stack.itemId}${
                    stack.quantity > 1 ? ` ×${stack.quantity}` : ''
                  }`
                : (slot?.['Display Name'] ?? slotId)

              return (
                <li key={slotId}>
                  <HoldTile
                    className={stack ? 'equip-slot-tile filled' : 'equip-slot-tile empty'}
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
                    {stack && stack.quantity > 1 && (
                      <span className="bag-item-qty">{stack.quantity}</span>
                    )}
                  </HoldTile>
                </li>
              )
            })}
          </ul>
          <p className="muted tiny">Hold a slot for its name. Tap equipped gear to unequip.</p>
        </section>
      )}
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
