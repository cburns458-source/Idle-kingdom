import { useEffect, useId, useRef, useState } from 'react'

export type AppScreen =
  | 'location'
  | 'map'
  | 'skills'
  | 'inventory'
  | 'log'
  | 'leaderboards'
  | 'guilds'
  | 'citadel'
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

const PRIMARY_ITEMS: { id: 'skills' | 'inventory'; label: string }[] = [
  { id: 'skills', label: 'Skills' },
  { id: 'inventory', label: 'Inventory' },
]

const NEST_ITEMS: { id: Exclude<AppScreen, 'map' | 'location' | 'skills' | 'inventory'>; label: string }[] =
  [
    { id: 'log', label: 'Log' },
    { id: 'leaderboards', label: 'Leaderboards' },
    { id: 'guilds', label: 'Guilds' },
    { id: 'citadel', label: 'Citadel' },
    { id: 'settings', label: 'Menu' },
  ]

const NEST_SCREEN_IDS = new Set(NEST_ITEMS.map((item) => item.id))

export function BottomNav({
  screen,
  onChange,
  currentLocationName,
  onOpenMainMap,
}: BottomNavProps) {
  const lastLocationTapRef = useRef(0)
  const nestRef = useRef<HTMLDivElement | null>(null)
  const menuButtonRef = useRef<HTMLButtonElement | null>(null)
  const [nestOpen, setNestOpen] = useState(false)
  const nestListId = useId()
  const nestActive = nestOpen || NEST_SCREEN_IDS.has(screen as (typeof NEST_ITEMS)[number]['id'])

  function handleLocationActivate() {
    const now = Date.now()
    if (now - lastLocationTapRef.current <= DOUBLE_TAP_MS) {
      lastLocationTapRef.current = 0
      setNestOpen(false)
      onOpenMainMap()
      return
    }
    lastLocationTapRef.current = now
    setNestOpen(false)
    onChange('location')
  }

  function selectNestItem(id: (typeof NEST_ITEMS)[number]['id']) {
    setNestOpen(false)
    onChange(id)
  }

  useEffect(() => {
    if (!nestOpen) return

    function onPointerDown(event: PointerEvent) {
      const target = event.target as Node | null
      if (!target) return
      if (nestRef.current?.contains(target) || menuButtonRef.current?.contains(target)) return
      setNestOpen(false)
    }

    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') setNestOpen(false)
    }

    document.addEventListener('pointerdown', onPointerDown)
    document.addEventListener('keydown', onKeyDown)
    return () => {
      document.removeEventListener('pointerdown', onPointerDown)
      document.removeEventListener('keydown', onKeyDown)
    }
  }, [nestOpen])

  return (
    <nav className="bottom-nav" aria-label="Main">
      <button
        type="button"
        className={screen === 'location' ? 'nav-btn active' : 'nav-btn'}
        onClick={handleLocationActivate}
        onDoubleClick={(event) => {
          event.preventDefault()
          lastLocationTapRef.current = 0
          setNestOpen(false)
          onOpenMainMap()
        }}
        title={`${currentLocationName} (double-tap for world map)`}
      >
        {currentLocationName}
      </button>
      {PRIMARY_ITEMS.map((item) => (
        <button
          key={item.id}
          type="button"
          className={screen === item.id ? 'nav-btn active' : 'nav-btn'}
          onClick={() => {
            setNestOpen(false)
            onChange(item.id)
          }}
        >
          {item.label}
        </button>
      ))}
      <div className="nav-menu-nest" ref={nestRef}>
        {nestOpen && (
          <div className="nav-menu-nest-popup" role="menu" id={nestListId} aria-label="More screens">
            {NEST_ITEMS.map((item) => (
              <button
                key={item.id}
                type="button"
                role="menuitem"
                className={
                  screen === item.id ? 'nav-menu-nest-item active' : 'nav-menu-nest-item'
                }
                onClick={() => selectNestItem(item.id)}
              >
                {item.label}
              </button>
            ))}
          </div>
        )}
        <button
          ref={menuButtonRef}
          type="button"
          className={nestActive ? 'nav-btn active' : 'nav-btn'}
          aria-label="Open menu nest"
          aria-haspopup="menu"
          aria-expanded={nestOpen}
          aria-controls={nestOpen ? nestListId : undefined}
          onClick={() => setNestOpen((open) => !open)}
        >
          <span className="nav-btn-icon" aria-hidden>
            ☰
          </span>
        </button>
      </div>
    </nav>
  )
}
