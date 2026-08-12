import { BUILDINGS } from './game/buildings'
import { buildingCost, canAfford, goldPerSecond } from './game/engine'
import { formatNumber } from './game/format'
import { useGame } from './hooks/useGame'

export default function App() {
  const { state, collectTaxes, buyBuilding, reset } = useGame()
  const gps = goldPerSecond(state)

  return (
    <div className="app">
      <header className="header">
        <h1>
          <span className="crown">👑</span> Idle Kingdom
        </h1>
        <p className="tagline">Rule the realm, one coin at a time.</p>
      </header>

      <section className="treasury">
        <div className="gold" aria-label="gold">
          {formatNumber(state.gold)} <span className="coin">🪙</span>
        </div>
        <div className="gps">{formatNumber(gps)} gold / sec</div>
        <button className="collect" onClick={collectTaxes}>
          Collect Taxes <span aria-hidden>💰</span>
        </button>
      </section>

      <section className="shop">
        <h2>Buildings</h2>
        <ul className="building-list">
          {BUILDINGS.map((def) => {
            const owned = state.buildings[def.id] ?? 0
            const cost = buildingCost(def.id, owned)
            const affordable = canAfford(state, def.id)
            return (
              <li key={def.id} className="building">
                <div className="building-icon" aria-hidden>
                  {def.icon}
                </div>
                <div className="building-info">
                  <div className="building-name">
                    {def.name}
                    <span className="building-owned">×{owned}</span>
                  </div>
                  <div className="building-desc">{def.description}</div>
                  <div className="building-prod">
                    +{formatNumber(def.production)} gold/sec each
                  </div>
                </div>
                <button
                  className="buy"
                  disabled={!affordable}
                  onClick={() => buyBuilding(def.id)}
                >
                  Buy
                  <span className="cost">{formatNumber(cost)} 🪙</span>
                </button>
              </li>
            )
          })}
        </ul>
      </section>

      <footer className="footer">
        <div className="stats">
          <span>Total earned: {formatNumber(state.totalEarned)} 🪙</span>
          <span>Taxes collected: {state.clicks}</span>
        </div>
        <button className="reset" onClick={reset}>
          Reset kingdom
        </button>
      </footer>
    </div>
  )
}
