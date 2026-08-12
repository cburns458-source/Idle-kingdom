import { fireEvent, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import App from './App'

describe('<App />', () => {
  beforeEach(() => localStorage.clear())
  afterEach(() => localStorage.clear())

  it('renders the kingdom title', () => {
    render(<App />)
    expect(screen.getByText(/Idle Kingdom/i)).toBeInTheDocument()
  })

  it('earns gold when collecting taxes and enables buying a farm', () => {
    render(<App />)
    const collect = screen.getByRole('button', { name: /collect taxes/i })
    const farmButton = screen.getAllByRole('button', { name: /buy/i })[0]

    expect(farmButton).toBeDisabled()
    for (let i = 0; i < 15; i++) fireEvent.click(collect)

    expect(screen.getByLabelText('gold').textContent).toContain('15')
    expect(farmButton).toBeEnabled()

    fireEvent.click(farmButton)
    expect(screen.getByText('×1')).toBeInTheDocument()
  })
})
