import { appearanceCategoryLabel, appearanceOptions } from '../game/cosmetics/appearance'
import type { GameDatabase } from '../game/data/types'
import { APPEARANCE_CATEGORIES, type PlayerAppearance } from '../game/save/types'

interface AppearancePickerProps {
  db: GameDatabase
  value: PlayerAppearance
  onSelect: (category: (typeof APPEARANCE_CATEGORIES)[number], optionId: string) => void
}

/** Shared appearance option grid — used at character creation and in the Wardrobe. */
export function AppearancePicker({ db, value, onSelect }: AppearancePickerProps) {
  return (
    <div className="appearance-picker">
      {APPEARANCE_CATEGORIES.map((category) => (
        <div key={category} className="appearance-picker-row">
          <p className="field-label">{appearanceCategoryLabel(category)}</p>
          <div className="appearance-option-row" role="radiogroup" aria-label={appearanceCategoryLabel(category)}>
            {appearanceOptions(db, category).map((option) => {
              const id = option['Appearance Option ID']
              const selected = value[category] === id
              const swatch = option['Swatch Color']
              return (
                <button
                  key={id}
                  type="button"
                  role="radio"
                  aria-checked={selected}
                  className={[
                    'appearance-option-tile',
                    swatch ? 'swatch' : '',
                    selected ? 'selected' : '',
                  ]
                    .filter(Boolean)
                    .join(' ')}
                  style={swatch ? { backgroundColor: swatch } : undefined}
                  title={option['Display Name']}
                  onClick={() => onSelect(category, id)}
                >
                  {swatch ? null : option['Display Name']}
                </button>
              )
            })}
          </div>
        </div>
      ))}
    </div>
  )
}
