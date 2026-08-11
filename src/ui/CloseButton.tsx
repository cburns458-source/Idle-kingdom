interface CloseButtonProps {
  onClick: () => void
  label?: string
  className?: string
}

/** Small round red × icon used to dismiss panels and dialogs. */
export function CloseButton({ onClick, label = 'Close', className = '' }: CloseButtonProps) {
  return (
    <button
      type="button"
      className={`close-icon-btn ${className}`.trim()}
      onClick={onClick}
      aria-label={label}
      title={label}
    >
      <span aria-hidden>×</span>
    </button>
  )
}
