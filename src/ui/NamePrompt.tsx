import { useState } from 'react'
import { CHARACTER_NAME_MAX_LENGTH } from '../game/save/types'
import { isValidCharacterName, normalizeCharacterName } from '../game/save/characterName'

interface NamePromptProps {
  title?: string
  initialName?: string
  submitLabel?: string
  onSubmit: (name: string) => void
  onCancel?: () => void
}

export function NamePrompt({
  title = 'Name your character',
  initialName = '',
  submitLabel = 'Begin',
  onSubmit,
  onCancel,
}: NamePromptProps) {
  const [value, setValue] = useState(initialName)
  const valid = isValidCharacterName(value)

  return (
    <section className="panel name-prompt">
      <h1>{title}</h1>
      <p className="lead">Choose a name for your adventurer in Idale.</p>
      <label className="field-label" htmlFor="character-name-input">
        Character name
      </label>
      <input
        id="character-name-input"
        className="text-input"
        type="text"
        value={value}
        maxLength={CHARACTER_NAME_MAX_LENGTH}
        autoComplete="off"
        autoFocus
        placeholder="Enter a name"
        onChange={(event) => setValue(event.target.value)}
        onKeyDown={(event) => {
          if (event.key === 'Enter' && valid) {
            const name = normalizeCharacterName(value)
            if (name) onSubmit(name)
          }
        }}
      />
      <p className="muted tiny">{value.trim().length}/{CHARACTER_NAME_MAX_LENGTH}</p>
      <div className="button-row">
        {onCancel && (
          <button type="button" className="btn secondary" onClick={onCancel}>
            Cancel
          </button>
        )}
        <button
          type="button"
          className="btn primary"
          disabled={!valid}
          onClick={() => {
            const name = normalizeCharacterName(value)
            if (name) onSubmit(name)
          }}
        >
          {submitLabel}
        </button>
      </div>
    </section>
  )
}
