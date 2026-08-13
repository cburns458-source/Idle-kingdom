import { ItemIcon } from './itemIcons'
import type { CosmeticUnlockNotice } from '../game/cosmetics/wardrobe'
import type { ItemRow } from '../game/data/types'

interface WardrobeUnlockPopupProps {
  notice: CosmeticUnlockNotice
  item: ItemRow | undefined
  onClose: () => void
}

export function WardrobeUnlockPopup({ notice, item, onClose }: WardrobeUnlockPopupProps) {
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
          <strong>{notice.name}</strong>
        </div>
        <p className="lead">It has been added to your Wardrobe.</p>
        {notice.hint && <p className="muted">{notice.hint}</p>}
        <button type="button" className="btn primary" onClick={onClose}>
          Nice!
        </button>
      </div>
    </div>
  )
}
