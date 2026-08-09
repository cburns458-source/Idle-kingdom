export type AppScreen = 'location' | 'map' | 'skills' | 'inventory' | 'log' | 'settings'

interface BottomNavProps {
  screen: AppScreen
  onChange: (screen: AppScreen) => void
  mapDisabled?: boolean
}

const ITEMS: { id: AppScreen; label: string }[] = [
  { id: 'location', label: 'Current' },
  { id: 'map', label: 'Map' },
  { id: 'skills', label: 'Stats' },
  { id: 'inventory', label: 'Items' },
  { id: 'log', label: 'Log' },
  { id: 'settings', label: 'Menu' },
]

export function BottomNav({ screen, onChange, mapDisabled = false }: BottomNavProps) {
  return (
    <nav className="bottom-nav" aria-label="Main">
      {ITEMS.map((item) => (
        <button
          key={item.id}
          type="button"
          className={screen === item.id ? 'nav-btn active' : 'nav-btn'}
          disabled={item.id === 'map' && mapDisabled}
          onClick={() => onChange(item.id)}
        >
          {item.label}
        </button>
      ))}
    </nav>
  )
}
