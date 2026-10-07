/**
 * Seeded PRNG shared with the Dart client so parity fixtures replay exactly.
 *
 * Production code keeps its `Math.random` defaults; this is injected wherever a
 * `RandomFn` is accepted so a scenario can be recorded and replayed. The Dart
 * port in `packages/ik_rules/lib/src/rng/mulberry32.dart` performs the same
 * 32-bit arithmetic and must stay in lockstep - `parity/fixtures/rng` proves it.
 */
export type RandomFn = () => number

const UINT32_DIVISOR = 4294967296

function stepMulberry32(state: number): { state: number; value: number } {
  const next = (state + 0x6d2b79f5) >>> 0
  let t = next
  t = Math.imul(t ^ (t >>> 15), t | 1)
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
  return { state: next, value: ((t ^ (t >>> 14)) >>> 0) / UINT32_DIVISOR }
}

export function mulberry32(seed: number): RandomFn {
  let state = seed >>> 0
  return () => {
    const stepped = stepMulberry32(state)
    state = stepped.state
    return stepped.value
  }
}

/** Same stream as [mulberry32], with a readable state for hosted saves. */
export function createTrackedMulberry32(initialState: number): {
  random: RandomFn
  getState: () => number
} {
  let state = initialState >>> 0
  return {
    random: () => {
      const stepped = stepMulberry32(state)
      state = stepped.state
      return stepped.value
    },
    getState: () => state,
  }
}

/** Draws [count] values, for recording a reproducible sequence. */
export function drawSequence(random: RandomFn, count: number): number[] {
  const draws: number[] = []
  for (let index = 0; index < count; index += 1) draws.push(random())
  return draws
}
