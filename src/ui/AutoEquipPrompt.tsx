import type { AutoEquipProposal } from '../game/equipment/autoEquip'

interface AutoEquipPromptProps {
  proposal: AutoEquipProposal
  onCancel: () => void
  onConfirm: () => void
}

function capabilityLabel(capability: string): string {
  return capability.replaceAll('_', ' ')
}

export function AutoEquipPrompt({ proposal, onCancel, onConfirm }: AutoEquipPromptProps) {
  const tools = proposal.capabilities.map(capabilityLabel).join(', ')

  return (
    <div
      className="destroy-confirm-overlay"
      role="dialog"
      aria-modal="true"
      aria-labelledby="auto-equip-title"
    >
      <div className="panel destroy-confirm-card">
        <h2 id="auto-equip-title">Equip required tool?</h2>
        <p className="lead">{proposal.failureReason}</p>
        <p className="muted">
          Equip <strong>{proposal.itemName}</strong>
          {tools ? ` (${tools})` : ''} from your bag and start this activity?
        </p>
        <div className="button-row">
          <button type="button" className="btn secondary" onClick={onCancel}>
            Not now
          </button>
          <button type="button" className="btn primary" onClick={onConfirm}>
            Equip & Start
          </button>
        </div>
      </div>
    </div>
  )
}
