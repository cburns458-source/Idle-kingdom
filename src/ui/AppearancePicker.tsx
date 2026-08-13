import type { CSSProperties } from 'react'
import { appearanceSliders, type AppearanceSlider } from '../game/cosmetics/wardrobe'
import type { GameDatabase } from '../game/data/types'
import type { AppearanceCategory, PlayerAppearance } from '../game/save/types'

interface AppearancePickerProps {
  db: GameDatabase
  value: PlayerAppearance
  onSelect: (category: AppearanceCategory, optionId: string) => void
}

/** Shared appearance sliders — used at character creation and in the Wardrobe. */
export function AppearancePicker({ db, value, onSelect }: AppearancePickerProps) {
  return (
    <div className="appearance-picker">
      {appearanceSliders(db, value).map((slider) => (
        <AppearanceSliderRow
          key={slider.category}
          slider={slider}
          onSelect={(optionId) => onSelect(slider.category, optionId)}
        />
      ))}
    </div>
  )
}

/** Bare slider with discrete stops — no value text or swatch, just drag/click to a stop. */
function AppearanceSliderRow({
  slider,
  onSelect,
}: {
  slider: AppearanceSlider
  onSelect: (optionId: string) => void
}) {
  const maxIndex = slider.optionIds.length - 1
  const index = slider.selectedIndex
  const fillPercent = maxIndex > 0 ? (index / maxIndex) * 100 : 0

  return (
    <div className="appearance-picker-row">
      <p className="field-label">{slider.label}</p>
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
            const next = slider.optionIds[Number(event.target.value)]
            if (next) onSelect(next)
          }}
          aria-label={slider.label}
        />
        <div className="appearance-slider-ticks" aria-hidden>
          {slider.optionIds.map((optionId, tickIndex) => (
            <span
              key={optionId}
              className={`appearance-slider-tick${tickIndex <= index ? ' filled' : ''}`}
            />
          ))}
        </div>
      </div>
    </div>
  )
}
