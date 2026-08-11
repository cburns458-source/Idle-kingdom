import type { CSSProperties } from 'react'
import { appearanceCategoryLabel, appearanceOptions } from '../game/cosmetics/appearance'
import type { GameDatabase } from '../game/data/types'
import { APPEARANCE_CATEGORIES, type PlayerAppearance } from '../game/save/types'

type AppearanceCategory = (typeof APPEARANCE_CATEGORIES)[number]

interface AppearancePickerProps {
  db: GameDatabase
  value: PlayerAppearance
  onSelect: (category: AppearanceCategory, optionId: string) => void
}

/** Shared appearance sliders — used at character creation and in the Wardrobe. */
export function AppearancePicker({ db, value, onSelect }: AppearancePickerProps) {
  return (
    <div className="appearance-picker">
      {APPEARANCE_CATEGORIES.map((category) => (
        <AppearanceSlider
          key={category}
          db={db}
          category={category}
          selectedId={value[category]}
          onSelect={(optionId) => onSelect(category, optionId)}
        />
      ))}
    </div>
  )
}

/** Bare slider with discrete stops — no value text or swatch, just drag/click to a stop. */
function AppearanceSlider({
  db,
  category,
  selectedId,
  onSelect,
}: {
  db: GameDatabase
  category: AppearanceCategory
  selectedId: string
  onSelect: (optionId: string) => void
}) {
  const options = appearanceOptions(db, category)
  if (options.length === 0) return null

  const maxIndex = options.length - 1
  const index = Math.max(0, options.findIndex((option) => option['Appearance Option ID'] === selectedId))
  const label = appearanceCategoryLabel(category)
  const fillPercent = maxIndex > 0 ? (index / maxIndex) * 100 : 0

  return (
    <div className="appearance-picker-row">
      <p className="field-label">{label}</p>
      <div className="appearance-slider-track-wrap">
        <input
          type="range"
          className="appearance-slider-input"
          min={0}
          max={maxIndex}
          step={1}
          value={index}
          disabled={maxIndex <= 0}
          style={{ '--slider-fill': `${fillPercent}%` } as CSSProperties}
          onChange={(event) => {
            const next = options[Number(event.target.value)]
            if (next) onSelect(next['Appearance Option ID'])
          }}
          aria-label={label}
        />
        <div className="appearance-slider-ticks" aria-hidden>
          {options.map((option, tickIndex) => (
            <span
              key={option['Appearance Option ID']}
              className={`appearance-slider-tick${tickIndex <= index ? ' filled' : ''}`}
            />
          ))}
        </div>
      </div>
    </div>
  )
}
