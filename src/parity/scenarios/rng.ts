import { drawSequence, mulberry32 } from '../../game/rng/mulberry32'
import { canonicalNumber } from '../canonicalJson'
import { scenario, type ParityScenario } from '../types'

/** Seeds chosen to cover zero, small, signed-bit, and full-width state. */
const SEEDS = [0, 1, 42, 12345, 2147483647, 4294967295]

const NUMBER_FORMS = [
  0, -0, 1, -1, 7, 1000000, 0.5, -0.5, 0.1, 2 / 3, 1e-7, 1.5e21, 9007199254740991, 123.456,
]

export const rngScenarios: ParityScenario[] = [
  ...SEEDS.map((seed) =>
    scenario('rng', `mulberry32-seed-${seed}`, { seed, draws: 32 }, () => ({
      values: drawSequence(mulberry32(seed), 32),
    })),
  ),
  // Guards the harness itself: if the two canonical number encoders ever
  // disagree, every other fixture comparison becomes untrustworthy.
  scenario('parity', 'canonical-numbers', { values: NUMBER_FORMS }, () => ({
    encoded: NUMBER_FORMS.map(canonicalNumber),
  })),
]
