import { useState } from 'react'
import { withAppearanceOption } from '../game/cosmetics/appearance'
import type { GameDatabase } from '../game/data/types'
import { races } from '../game/races/races'
import type { PlayerAppearance } from '../game/save/types'
import { AppearancePicker } from './AppearancePicker'
import { NamePrompt } from './NamePrompt'
import { playerPortraitAssetPath } from '../game/assets/playerAssets'
import { RacePicker } from './RacePicker'

interface NewCharacterFlowProps {
  db: GameDatabase
  initialAppearance: PlayerAppearance
  onComplete: (name: string, raceId: string, appearance: PlayerAppearance) => void
}

/** First-run flow: name → race → starting appearance. */
export function NewCharacterFlow({ db, initialAppearance, onComplete }: NewCharacterFlowProps) {
  const [name, setName] = useState<string | null>(null)
  const [raceId, setRaceId] = useState<string | null>(null)
  const [selectedRaceId, setSelectedRaceId] = useState<string | null>(
    () => races(db)[0]?.['Race ID'] ?? null,
  )
  const [appearance, setAppearance] = useState<PlayerAppearance>(initialAppearance)

  if (name == null) {
    return <NamePrompt onSubmit={setName} />
  }

  if (raceId == null) {
    return (
      <section className="panel name-prompt race-creation-step">
        <h1>Choose your race</h1>
        <p className="lead">
          Pick a race for {name}. Bonuses are provisional and may change with balance.
        </p>
        <RacePicker
          db={db}
          selectedRaceId={selectedRaceId}
          onSelect={setSelectedRaceId}
          showStartingItems
        />
        <div className="button-row">
          <button type="button" className="btn secondary" onClick={() => setName(null)}>
            Back
          </button>
          <button
            type="button"
            className="btn primary"
            disabled={!selectedRaceId}
            onClick={() => {
              if (selectedRaceId) setRaceId(selectedRaceId)
            }}
          >
            Continue
          </button>
        </div>
      </section>
    )
  }

  return (
    <section className="panel name-prompt appearance-creation-step">
      <h1>Choose your look</h1>
      <p className="lead">
        Pick a starting appearance for {name} — change it anytime from the Wardrobe.
      </p>
      <div className="appearance-creation-preview">
        <img
          src={playerPortraitAssetPath(appearance)}
          alt=""
          className="appearance-creation-portrait"
        />
      </div>
      <AppearancePicker
        db={db}
        value={appearance}
        onSelect={(category, optionId) =>
          setAppearance((current) => withAppearanceOption(current, category, optionId))
        }
      />
      <div className="button-row">
        <button type="button" className="btn secondary" onClick={() => setRaceId(null)}>
          Back
        </button>
        <button
          type="button"
          className="btn primary"
          onClick={() => onComplete(name, raceId, appearance)}
        >
          Begin adventure
        </button>
      </div>
    </section>
  )
}

interface RaceOnlyPickerProps {
  db: GameDatabase
  title?: string
  lead?: string
  submitLabel?: string
  showStartingItems?: boolean
  onComplete: (raceId: string) => void
  onCancel?: () => void
}

/** One-time / menu race selection without name or appearance steps. */
export function RaceOnlyPicker({
  db,
  title = 'Choose your race',
  lead = 'Pick a playable race to continue.',
  submitLabel = 'Confirm race',
  showStartingItems = true,
  onComplete,
  onCancel,
}: RaceOnlyPickerProps) {
  const [selectedRaceId, setSelectedRaceId] = useState<string | null>(
    () => races(db)[0]?.['Race ID'] ?? null,
  )

  return (
    <section className="panel name-prompt race-creation-step">
      <h1>{title}</h1>
      <p className="lead">{lead}</p>
      <RacePicker
        db={db}
        selectedRaceId={selectedRaceId}
        onSelect={setSelectedRaceId}
        showStartingItems={showStartingItems}
      />
      <div className="button-row">
        {onCancel && (
          <button type="button" className="btn secondary" onClick={onCancel}>
            Cancel
          </button>
        )}
        <button
          type="button"
          className="btn primary"
          disabled={!selectedRaceId}
          onClick={() => {
            if (selectedRaceId) onComplete(selectedRaceId)
          }}
        >
          {submitLabel}
        </button>
      </div>
    </section>
  )
}
