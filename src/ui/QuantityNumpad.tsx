import { useEffect, useRef, useState, type ReactNode } from 'react'
import { createPortal } from 'react-dom'

export interface QuantityNumpadProps {
  title: string
  subtitle?: ReactNode
  /** Extra lines under the title (available, afford, etc.). */
  details?: ReactNode
  confirmLabel: string
  initialValue?: number
  max?: number
  min?: number
  error?: string | null
  onCancel: () => void
  onConfirm: (quantity: number) => void
  /** When true, amount field can be typed (desktop). Default true. */
  allowTypedInput?: boolean
}

function isCoarsePointer(): boolean {
  if (typeof window === 'undefined') return false
  return window.matchMedia('(pointer: coarse)').matches
}

export function QuantityNumpad({
  title,
  subtitle,
  details,
  confirmLabel,
  initialValue = 1,
  max,
  min = 1,
  error,
  onCancel,
  onConfirm,
  allowTypedInput = true,
}: QuantityNumpadProps) {
  const [text, setText] = useState(String(Math.max(min, initialValue)))
  const [localError, setLocalError] = useState<string | null>(null)
  const inputRef = useRef<HTMLInputElement | null>(null)
  const touchUi = isCoarsePointer()

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') {
        event.preventDefault()
        onCancel()
      }
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [onCancel])

  function appendDigit(digit: string) {
    setLocalError(null)
    setText((current) => {
      const next = current === '0' ? digit : `${current}${digit}`
      if (next.length > 9) return current
      return next
    })
  }

  function backspace() {
    setLocalError(null)
    setText((current) => (current.length <= 1 ? '0' : current.slice(0, -1)))
  }

  function clear() {
    setLocalError(null)
    setText('0')
  }

  function setMax() {
    setLocalError(null)
    const ceiling = typeof max === 'number' ? Math.max(min, max) : min
    setText(String(ceiling))
  }

  function confirm() {
    const parsed = Number(text.trim())
    if (!Number.isFinite(parsed) || !Number.isInteger(parsed) || parsed < min) {
      setLocalError(`Enter a whole number of at least ${min}.`)
      return
    }
    if (typeof max === 'number' && parsed > max) {
      setLocalError(`Maximum is ${max.toLocaleString()}.`)
      return
    }
    onConfirm(parsed)
  }

  const displayError = localError ?? error

  return createPortal(
    <div
      className="quest-reward-overlay shop-qty-overlay"
      role="dialog"
      aria-modal="true"
      aria-labelledby="qty-numpad-title"
    >
      <div className="panel quest-reward-card shop-qty-card qty-numpad-card">
        {subtitle && <p className="muted tiny">{subtitle}</p>}
        <h2 id="qty-numpad-title">{title}</h2>
        {details}
        <label className="field-label" htmlFor="qty-numpad-input">
          Amount
        </label>
        <div className="shop-qty-row">
          <input
            id="qty-numpad-input"
            ref={inputRef}
            className="text-input"
            type="text"
            inputMode="numeric"
            autoComplete="off"
            readOnly={touchUi || !allowTypedInput}
            value={text}
            onChange={(event) => {
              if (touchUi || !allowTypedInput) return
              setLocalError(null)
              setText(event.target.value.replace(/[^\d]/g, '') || '0')
            }}
            onKeyDown={(event) => {
              if (event.key === 'Enter') {
                event.preventDefault()
                confirm()
              }
            }}
          />
          <button
            type="button"
            className="btn secondary"
            disabled={typeof max === 'number' ? max < min : false}
            onClick={setMax}
          >
            Max
          </button>
        </div>

        <div className="qty-numpad" aria-label="Quantity keypad">
          {['1', '2', '3', '4', '5', '6', '7', '8', '9', 'C', '0', '⌫'].map((key) => (
            <button
              key={key}
              type="button"
              className="qty-numpad-key"
              onClick={() => {
                if (key === 'C') clear()
                else if (key === '⌫') backspace()
                else appendDigit(key)
              }}
            >
              {key}
            </button>
          ))}
        </div>

        {displayError && <p className="danger-note">{displayError}</p>}
        <div className="button-row shop-qty-actions">
          <button type="button" className="btn secondary" onClick={onCancel}>
            Cancel
          </button>
          <button type="button" className="btn primary" onClick={confirm}>
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>,
    document.body,
  )
}
