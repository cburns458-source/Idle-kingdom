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

export function mulberry32(seed: number): RandomFn {
  let state = seed >>> 0
  return () => {
    state = (state + 0x6d2b79f5) >>> 0
    let t = state
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / UINT32_DIVISOR
  }
}

/** Draws [count] values, for recording a reproducible sequence. */
export function drawSequence(random: RandomFn, count: number): number[] {
  const draws: number[] = []
  for (let index = 0; index < count; index += 1) draws.push(random())
  return draws
}
