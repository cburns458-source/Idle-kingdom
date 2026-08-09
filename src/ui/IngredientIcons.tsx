import { useEffect, useRef, useState, type ReactNode } from 'react'
import type { ItemRow } from '../game/data/types'
import { ItemIcon } from './itemIcons'

export interface IngredientIconEntry {
  itemId: string
  item: ItemRow | undefined
  need: number
  owned: number
}

/** Compact required-ingredient icons with quantity badges and hold/hover name tooltips. */
export function IngredientIconList({ ingredients }: { ingredients: IngredientIconEntry[] }) {
  const [heldTip, setHeldTip] = useState<string | null>(null)
  if (ingredients.length === 0) return null
  return (
    <ul className="ingredient-icon-list">
      {ingredients.map((entry) => {
        const short = entry.owned < entry.need
        const name = entry.item?.['Display Name'] ?? entry.itemId
        const tipId = entry.itemId
        const tipText = `${name}\n${entry.owned}`
        return (
          <li key={entry.itemId}>
            <IngredientTipTile
              className={short ? 'ingredient-icon-tile short' : 'ingredient-icon-tile'}
              ariaLabel={tipText}
              tipText={tipText}
              showingTip={heldTip === tipId}
              onTipStart={() => setHeldTip(tipId)}
              onTipEnd={() => setHeldTip((current) => (current === tipId ? null : current))}
            >
              <ItemIcon item={entry.item} />
              <span className="ingredient-qty">×{entry.need}</span>
            </IngredientTipTile>
          </li>
        )
      })}
    </ul>
  )
}

function IngredientTipTile({
  className,
  ariaLabel,
  tipText,
  showingTip,
  onTipStart,
  onTipEnd,
  children,
}: {
  className: string
  ariaLabel: string
  tipText: string
  showingTip: boolean
  onTipStart: () => void
  onTipEnd: () => void
  children: ReactNode
}) {
  const timerRef = useRef<number | null>(null)

  useEffect(() => {
    return () => {
      if (timerRef.current != null) window.clearTimeout(timerRef.current)
    }
  }, [])

  function clearTimer() {
    if (timerRef.current != null) {
      window.clearTimeout(timerRef.current)
      timerRef.current = null
    }
  }

  function beginTip() {
    clearTimer()
    timerRef.current = window.setTimeout(() => {
      onTipStart()
    }, 180)
  }

  function endTip() {
    clearTimer()
    onTipEnd()
  }

  return (
    <button
      type="button"
      className={showingTip ? `${className} showing-tip` : className}
      aria-label={ariaLabel}
      onPointerDown={beginTip}
      onPointerUp={endTip}
      onPointerLeave={endTip}
      onPointerCancel={endTip}
      onPointerEnter={beginTip}
      onFocus={onTipStart}
      onBlur={endTip}
      onContextMenu={(event) => event.preventDefault()}
    >
      {children}
      {showingTip && (
        <span className="item-name-tooltip ingredient-name-tooltip" role="tooltip">
          {tipText}
        </span>
      )}
    </button>
  )
}
