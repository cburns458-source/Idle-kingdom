import { ItemIcon } from './itemIcons'
import type { ItemRow } from '../game/data/types'

interface WardrobeUnlockPopupProps {
  cosmeticName: string
  item: ItemRow | undefined
  /** True only for the player's very first cosmetic ever — shows the extra Wardrobe hint. */
  isFirstEver: boolean
  onClose: () => void
}

export function WardrobeUnlockPopup({
  cosmeticName,
  item,
  isFirstEver,
  onClose,
}: WardrobeUnlockPopupProps) {
  return (
    <div
      className="quest-reward-overlay"
      role="dialog"
      aria-modal="true"
      aria-labelledby="wardrobe-unlock-title"
      onClick={(event) => {
        if (event.target === event.currentTarget) onClose()
      }}
    >
      <div className="panel quest-reward-card wardrobe-unlock-card">
        <p className="muted tiny">New Cosmetic</p>
        <h2 id="wardrobe-unlock-title">You found a Cosmetic!</h2>
        <div className="wardrobe-unlock-item">
          <ItemIcon item={item} />
          <strong>{cosmeticName}</strong>
        </div>
        <p className="lead">It has been added to your Wardrobe.</p>
        {isFirstEver && (
          <p className="muted">
            Tap your portrait in the top-left corner anytime to open the Wardrobe and equip it.
          </p>
        )}
        <button type="button" className="btn primary" onClick={onClose}>
          Nice!
        </button>
      </div>
    </div>
  )
}
