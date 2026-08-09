interface ProjectCompletePopupProps {
  projectName: string
  lines: string[]
  onClose: () => void
}

export function ProjectCompletePopup({
  projectName,
  lines,
  onClose,
}: ProjectCompletePopupProps) {
  return (
    <div
      className="quest-reward-overlay"
      role="dialog"
      aria-modal="true"
      aria-labelledby="project-complete-title"
    >
      <div className="panel quest-reward-card">
        <p className="muted tiny">Project complete</p>
        <h2 id="project-complete-title">{projectName}</h2>
        {lines.length > 0 ? (
          <ul className="quest-reward-list">
            {lines.map((line) => (
              <li key={line}>{line}</li>
            ))}
          </ul>
        ) : (
          <p className="lead">Project finished.</p>
        )}
        <button type="button" className="btn primary" onClick={onClose}>
          Continue
        </button>
      </div>
    </div>
  )
}
