import type { ItemRow } from '../game/data/types'
import { ItemIcon } from './itemIcons'

export interface IngredientIconEntry {
  itemId: string
  item: ItemRow | undefined
  need: number
  owned: number
}

/** Compact required-ingredient icons with quantity badges (name via tooltip). */
export function IngredientIconList({ ingredients }: { ingredients: IngredientIconEntry[] }) {
  if (ingredients.length === 0) return null
  return (
    <ul className="ingredient-icon-list">
      {ingredients.map((entry) => {
        const short = entry.owned < entry.need
        const name = entry.item?.['Display Name'] ?? entry.itemId
        return (
          <li
            key={entry.itemId}
            className={short ? 'ingredient-icon-tile short' : 'ingredient-icon-tile'}
            title={`${name} ×${entry.need} (have ${entry.owned})`}
          >
            <ItemIcon item={entry.item} />
            <span className="ingredient-qty">×{entry.need}</span>
            <span className="visually-hidden">
              {name} ×{entry.need}, have {entry.owned}
            </span>
          </li>
        )
      })}
    </ul>
  )
}
