export type AppScreen = 'location' | 'map' | 'skills' | 'inventory' | 'settings'

interface BottomNavProps {
  screen: AppScreen
  onChange: (screen: AppScreen) => void
}

const ITEMS: { id: AppScreen; label: string }[] = [
  { id: 'location', label: 'Current' },
  { id: 'skills', label: 'Skills' },
  { id: 'inventory', label: 'Items' },
  { id: 'settings', label: 'Menu' },
]

export function BottomNav({ screen, onChange }: BottomNavProps) {
  return (
    <nav className="bottom-nav" aria-label="Main">
      {ITEMS.map((item) => (
        <button
          key={item.id}
          type="button"
          className={screen === item.id ? 'nav-btn active' : 'nav-btn'}
          onClick={() => onChange(item.id)}
        >
          {item.label}
        </button>
      ))}
    </nav>
  )
}
