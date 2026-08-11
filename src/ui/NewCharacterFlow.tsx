import { useState } from 'react'
import type { GameDatabase } from '../game/data/types'
import type { PlayerAppearance } from '../game/save/types'
import { AppearancePicker } from './AppearancePicker'
import { NamePrompt } from './NamePrompt'

interface NewCharacterFlowProps {
  db: GameDatabase
  initialAppearance: PlayerAppearance
  onComplete: (name: string, appearance: PlayerAppearance) => void
}

/** First-run flow: name, then starting appearance, before entering the game. */
export function NewCharacterFlow({ db, initialAppearance, onComplete }: NewCharacterFlowProps) {
  const [name, setName] = useState<string | null>(null)
  const [appearance, setAppearance] = useState<PlayerAppearance>(initialAppearance)

  if (name == null) {
    return <NamePrompt onSubmit={setName} />
  }

  return (
    <section className="panel name-prompt appearance-creation-step">
      <h1>Choose your look</h1>
      <p className="lead">
        Pick a starting appearance for {name} — change it anytime from the Wardrobe.
      </p>
      <AppearancePicker
        db={db}
        value={appearance}
        onSelect={(category, optionId) =>
          setAppearance((current) => ({ ...current, [category]: optionId }))
        }
      />
      <div className="button-row">
        <button type="button" className="btn secondary" onClick={() => setName(null)}>
          Back
        </button>
        <button
          type="button"
          className="btn primary"
          onClick={() => onComplete(name, appearance)}
        >
          Begin adventure
        </button>
      </div>
    </section>
  )
}
