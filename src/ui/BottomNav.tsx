import { useRef } from 'react'

export type AppScreen =
  | 'location'
  | 'map'
  | 'skills'
  | 'inventory'
  | 'log'
  | 'social'
  | 'settings'

interface BottomNavProps {
  screen: AppScreen
  onChange: (screen: AppScreen) => void
  /** Exact display name of the player's current location. */
  currentLocationName: string
  /** Always opens the main world map. */
  onOpenMainMap: () => void
}

const DOUBLE_TAP_MS = 300

const ITEMS: { id: Exclude<AppScreen, 'map' | 'location'>; label: string }[] = [
  { id: 'skills', label: 'Skills' },
  { id: 'inventory', label: 'Inventory' },
  { id: 'log', label: 'Log' },
  { id: 'settings', label: 'Menu' },
]

export function BottomNav({
  screen,
  onChange,
  currentLocationName,
  onOpenMainMap,
}: BottomNavProps) {
  const lastLocationTapRef = useRef(0)

  function handleLocationActivate() {
    const now = Date.now()
    if (now - lastLocationTapRef.current <= DOUBLE_TAP_MS) {
      lastLocationTapRef.current = 0
      onOpenMainMap()
      return
    }
    lastLocationTapRef.current = now
    onChange('location')
  }

  return (
    <nav className="bottom-nav" aria-label="Main">
      <button
        type="button"
        className={screen === 'location' ? 'nav-btn active' : 'nav-btn'}
        onClick={handleLocationActivate}
        onDoubleClick={(event) => {
          event.preventDefault()
          lastLocationTapRef.current = 0
          onOpenMainMap()
        }}
        title={`${currentLocationName} (double-tap for world map)`}
      >
        {currentLocationName}
      </button>
      {ITEMS.map((item) => (
        <button
          key={item.id}
          type="button"
          className={screen === item.id ? 'nav-btn active' : 'nav-btn'}
          onClick={() => onChange(item.id)}
          aria-label={item.id === 'settings' ? 'Menu' : item.label}
        >
          {item.id === 'settings' ? (
            <span className="nav-btn-icon" aria-hidden>
              ☰
            </span>
          ) : (
            item.label
          )}
        </button>
      ))}
    </nav>
  )
}
