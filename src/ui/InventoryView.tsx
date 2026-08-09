import { useState } from 'react'
import type { LoadedDatabase } from '../game/data/loadDatabase'
import {
  equipItemFromInventory,
  equipmentRequirementFailure,
  unequipSlot,
} from '../game/equipment/loadout'
import { withRecalculatedVitals } from '../game/equipment/vitals'
import { playerDamageRange, playerDamageReduction, playerMaxHp } from '../game/combat/stats'
import type { PlayerSave } from '../game/save/types'
import { ItemIcon } from './itemIcons'

interface InventoryViewProps {
  save: PlayerSave
  database: LoadedDatabase
  onChangeSave: (save: PlayerSave) => void
}

export function InventoryView({ save, database, onChangeSave }: InventoryViewProps) {
  const [message, setMessage] = useState<string | null>(null)
  const db = database.launch
  const slots = [...db.EquipmentSlots].sort((a, b) =>
    a['Slot ID'].localeCompare(b['Slot ID']),
  )
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
      <section className="panel">
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
        {message && <p className="danger-note">{message}</p>}
      </section>

      <section className="panel">
        <h2>Equipment</h2>
        <ul className="equipment-slot-grid">
          {slots.map((slot) => {
            const stack = save.equipment.slots[slot['Slot ID']]
            const item = stack
              ? database.launchIndexes.itemsById.get(stack.itemId)
              : undefined
            return (
              <li key={slot['Slot ID']} className={stack ? 'filled' : 'empty'}>
                <div className="equipment-slot-main">
                  <ItemIcon item={item} />
                  <div>
                    <p className="muted tiny">{slot['Display Name']}</p>
                    <strong>
                      {item?.['Display Name'] ?? 'Empty'}
                      {stack && stack.quantity > 1 ? ` ×${stack.quantity}` : ''}
                    </strong>
                  </div>
                </div>
                {stack && (
                  <button
                    type="button"
                    className="btn secondary"
                    onClick={() => unequip(slot['Slot ID'])}
                  >
                    Unequip
                  </button>
                )}
              </li>
            )
          })}
        </ul>
      </section>

      <section className="panel">
        <h2>Bag</h2>
        {save.inventory.length === 0 ? (
          <p className="lead">No items yet. Fight or gather to fill this list.</p>
        ) : (
          <ul className="interaction-list inventory-bag-list">
            {save.inventory.map((stack) => {
              const item = database.launchIndexes.itemsById.get(stack.itemId)
              const equipment = db.Equipment.find((row) => row['Item ID'] === stack.itemId)
              const gate =
                equipment != null ? equipmentRequirementFailure(db, save, equipment) : null
              return (
                <li key={stack.itemId}>
                  <div className="inventory-bag-main">
                    <ItemIcon item={item} />
                    <div>
                      <strong>{item?.['Display Name'] ?? stack.itemId}</strong>
                      <p className="muted">
                        × {stack.quantity}
                        {equipment?.['Slot ID']
                          ? ` · ${
                              db.EquipmentSlots.find(
                                (slot) => slot['Slot ID'] === equipment['Slot ID'],
                              )?.['Display Name'] ?? 'Gear'
                            }`
                          : ''}
                      </p>
                      {gate && <p className="muted tiny">{gate}</p>}
                    </div>
                  </div>
                  {equipment?.['Slot ID'] && (
                    <button
                      type="button"
                      className="btn primary"
                      disabled={Boolean(gate)}
                      onClick={() => equipItem(stack.itemId)}
                    >
                      Equip
                    </button>
                  )}
                </li>
              )
            })}
          </ul>
        )}
        <p className="muted tiny">
          Stack and bag limits apply when defined in game data. Potion effects are not active yet.
        </p>
      </section>
    </section>
  )
}
