import { useState } from 'react'
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
  const [direction, setDirection] = useState<'next' | 'prev'>('next')
  if (options.length === 0) return null

  const index = Math.max(0, options.findIndex((option) => option['Appearance Option ID'] === selectedId))
  const current = options[index] ?? options[0]!

  function slide(delta: 1 | -1) {
    setDirection(delta > 0 ? 'next' : 'prev')
    const nextIndex = (index + delta + options.length) % options.length
    onSelect(options[nextIndex]!['Appearance Option ID'])
  }

  const swatch = current['Swatch Color']
  const label = appearanceCategoryLabel(category)

  return (
    <div className="appearance-picker-row">
      <p className="field-label">{label}</p>
      <div className="appearance-slider">
        <button
          type="button"
          className="appearance-slider-arrow"
          onClick={() => slide(-1)}
          disabled={options.length <= 1}
          aria-label={`Previous ${label.toLowerCase()}`}
        >
          ‹
        </button>
        <div className="appearance-slider-track">
          <div
            key={current['Appearance Option ID']}
            className={`appearance-slider-value appearance-slide-${direction}`}
          >
            {swatch && (
              <span className="appearance-slider-swatch" style={{ backgroundColor: swatch }} aria-hidden />
            )}
            <span className="appearance-slider-name">{current['Display Name']}</span>
          </div>
        </div>
        <button
          type="button"
          className="appearance-slider-arrow"
          onClick={() => slide(1)}
          disabled={options.length <= 1}
          aria-label={`Next ${label.toLowerCase()}`}
        >
          ›
        </button>
      </div>
    </div>
  )
}
