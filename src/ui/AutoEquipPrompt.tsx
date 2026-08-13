import { autoEquipPromptView, type AutoEquipProposal } from '../game/equipment/autoEquip'

interface AutoEquipPromptProps {
  proposal: AutoEquipProposal
  onCancel: () => void
  onConfirm: () => void
}

export function AutoEquipPrompt({ proposal, onCancel, onConfirm }: AutoEquipPromptProps) {
  const prompt = autoEquipPromptView(proposal)

  return (
    <div
      className="destroy-confirm-overlay"
      role="dialog"
      aria-modal="true"
      aria-labelledby="auto-equip-title"
    >
      <div className="panel destroy-confirm-card">
        <h2 id="auto-equip-title">{prompt.title}</h2>
        <p className="lead">{prompt.reason}</p>
        <p className="muted">{prompt.question}</p>
        <div className="button-row">
          <button type="button" className="btn secondary" onClick={onCancel}>
            {prompt.cancelLabel}
          </button>
          <button type="button" className="btn primary" onClick={onConfirm}>
            {prompt.confirmLabel}
          </button>
        </div>
      </div>
    </div>
  )
}
