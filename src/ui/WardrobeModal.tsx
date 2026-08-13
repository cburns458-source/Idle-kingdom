import { useEffect, useState } from 'react'
import { createPortal } from 'react-dom'
import { setAppearanceOption } from '../game/cosmetics/appearance'
import { equipCosmetic } from '../game/cosmetics/cosmetics'
import { wardrobeSlotTabs, wardrobeSlotView } from '../game/cosmetics/wardrobe'
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
  const tabs = wardrobeSlotTabs(db)
  const [activeSlotId, setActiveSlotId] = useState(tabs[0]?.slotId ?? '')
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

  const slot = wardrobeSlotView(db, save, activeSlotId)
  const raceName = raceDisplayName(db, save.raceId)

  function equip(cosmeticId: string | null) {
    if (!slot) return
    const result = equipCosmetic(db, save, slot.slotId, cosmeticId)
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
            {raceName && <p className="wardrobe-race muted tiny">{raceName}</p>}
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
            {tabs.map((tab) => (
              <button
                key={tab.slotId}
                type="button"
                role="tab"
                aria-selected={tab.slotId === slot?.slotId}
                className={`wardrobe-tab${tab.slotId === slot?.slotId ? ' active' : ''}`}
                onClick={() => {
                  setActiveSlotId(tab.slotId)
                  setError(null)
                }}
              >
                {tab.label}
              </button>
            ))}
          </div>

          <div className="wardrobe-cosmetic-grid" role="list">
            <button
              type="button"
              role="listitem"
              className={`wardrobe-cosmetic-tile${slot?.equippedCosmeticId == null ? ' selected' : ''}`}
              onClick={() => equip(null)}
            >
              <span className="wardrobe-cosmetic-none">None</span>
            </button>
            {slot?.tiles.map((tile) => (
              <button
                key={tile.cosmeticId}
                type="button"
                role="listitem"
                className={`wardrobe-cosmetic-tile${tile.equipped ? ' selected' : ''}`}
                onClick={() => equip(tile.cosmeticId)}
                title={tile.name}
              >
                <ItemIcon item={db.Items.find((row) => row['Item ID'] === tile.itemId)} />
                <span className="wardrobe-cosmetic-name">{tile.name}</span>
              </button>
            ))}
            {slot && slot.tiles.length === 0 && (
              <p className="muted tiny wardrobe-cosmetic-empty">{slot.emptyNote}</p>
            )}
          </div>
          {error && <p className="danger-note">{error}</p>}
        </div>
      </div>
    </div>,
    document.body,
  )
}
