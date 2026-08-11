import { useEffect, useState } from 'react'
import { createPortal } from 'react-dom'
import { setAppearanceOption } from '../game/cosmetics/appearance'
import {
  cosmeticSlots,
  cosmeticsForSlot,
  equipCosmetic,
  equippedCosmeticId,
  isCosmeticUnlocked,
} from '../game/cosmetics/cosmetics'
import type { GameDatabase } from '../game/data/types'
import { raceDisplayName } from '../game/races/races'
import type { PlayerSave } from '../game/save/types'
import { playerPortraitAssetPath } from '../game/assets/playerAssets'
import { AppearancePicker } from './AppearancePicker'
import { CloseButton } from './CloseButton'
import { ItemIcon } from './itemIcons'

interface WardrobeModalProps {
  db: GameDatabase
  save: PlayerSave
  open: boolean
  onClose: () => void
  onChangeSave: (save: PlayerSave) => void
}

export function WardrobeModal({ db, save, open, onClose, onChangeSave }: WardrobeModalProps) {
  const slots = cosmeticSlots(db)
  const [activeSlotId, setActiveSlotId] = useState(slots[0]?.['Cosmetic Slot ID'] ?? '')
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!open) return
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') {
        event.preventDefault()
        onClose()
      }
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [open, onClose])

  if (!open) return null

  const activeSlot = slots.find((row) => row['Cosmetic Slot ID'] === activeSlotId) ?? slots[0]
  const activeSlotIdResolved = activeSlot?.['Cosmetic Slot ID'] ?? ''
  const owned = cosmeticsForSlot(db, activeSlotIdResolved).filter((row) =>
    isCosmeticUnlocked(save, row['Cosmetic ID']),
  )
  const equippedId = equippedCosmeticId(save, activeSlotIdResolved)

  function equip(cosmeticId: string | null) {
    const result = equipCosmetic(db, save, activeSlotIdResolved, cosmeticId)
    if (!result.ok) {
      setError(result.reason)
      return
    }
    setError(null)
    onChangeSave(result.save)
  }

  return createPortal(
    <div
      className="quest-reward-overlay wardrobe-overlay"
      role="dialog"
      aria-modal="true"
      aria-labelledby="wardrobe-title"
      onClick={onClose}
    >
      <div
        className="panel quest-reward-card wardrobe-card"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="activity-panel-head">
          <h2 id="wardrobe-title">Wardrobe</h2>
          <CloseButton onClick={onClose} />
        </div>

        <div className="wardrobe-top">
          <div className="wardrobe-portrait">
            <img
              src={playerPortraitAssetPath(save)}
              alt=""
              className="wardrobe-portrait-image"
            />
            {raceDisplayName(db, save.raceId) && (
              <p className="wardrobe-race muted tiny">{raceDisplayName(db, save.raceId)}</p>
            )}
          </div>
          <AppearancePicker
            db={db}
            value={save.appearance}
            onSelect={(category, optionId) => {
              const next = setAppearanceOption(db, save, category, optionId)
              if (next) onChangeSave(next)
            }}
          />
        </div>

        <div className="wardrobe-bottom">
          <div className="wardrobe-tabs" role="tablist" aria-label="Cosmetic slots">
            {slots.map((slot) => {
              const slotId = slot['Cosmetic Slot ID']
              return (
                <button
                  key={slotId}
                  type="button"
                  role="tab"
                  aria-selected={slotId === activeSlotIdResolved}
                  className={`wardrobe-tab${slotId === activeSlotIdResolved ? ' active' : ''}`}
                  onClick={() => {
                    setActiveSlotId(slotId)
                    setError(null)
                  }}
                >
                  {slot['Display Name']}
                </button>
              )
            })}
          </div>

          <div className="wardrobe-cosmetic-grid" role="list">
            <button
              type="button"
              role="listitem"
              className={`wardrobe-cosmetic-tile${equippedId == null ? ' selected' : ''}`}
              onClick={() => equip(null)}
            >
              <span className="wardrobe-cosmetic-none">None</span>
            </button>
            {owned.map((cosmetic) => {
              const cosmeticId = cosmetic['Cosmetic ID']
              const item = db.Items.find((row) => row['Item ID'] === cosmetic['Item ID'])
              return (
                <button
                  key={cosmeticId}
                  type="button"
                  role="listitem"
                  className={`wardrobe-cosmetic-tile${cosmeticId === equippedId ? ' selected' : ''}`}
                  onClick={() => equip(cosmeticId)}
                  title={item?.['Display Name'] ?? cosmeticId}
                >
                  <ItemIcon item={item} />
                  <span className="wardrobe-cosmetic-name">{item?.['Display Name'] ?? cosmeticId}</span>
                </button>
              )
            })}
            {owned.length === 0 && (
              <p className="muted tiny wardrobe-cosmetic-empty">
                No {activeSlot?.['Display Name'] ?? 'items'} unlocked yet.
              </p>
            )}
          </div>
          {error && <p className="danger-note">{error}</p>}
        </div>
      </div>
    </div>,
    document.body,
  )
}
