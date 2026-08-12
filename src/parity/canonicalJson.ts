/**
 * Canonical JSON encoding shared with `packages/ik_parity`.
 *
 * Parity comparison happens on these strings rather than on structures, so both
 * sides must agree on key order and number formatting. Dart separates `int` from
 * `double` where JavaScript has a single `number`, so `1` and `1.0` must encode
 * identically while `1` and `1.0000001` must not.
 *
 * Rules return `Infinity` for "no limit" quantities, so non-finite numbers encode
 * as the quoted strings JSON has no literals for. A fixture that happens to hold
 * the literal string `"Infinity"` encodes the same way on both sides, so the
 * ambiguity cannot make a mismatch look like a match.
 */

const JS_SAFE_INTEGER_LIMIT = 9007199254740992

export function canonicalJson(value: unknown): string {
  return write(value, [])
}

export function canonicalEquals(a: unknown, b: unknown): boolean {
  return canonicalJson(a) === canonicalJson(b)
}

export function canonicalNumber(value: number): string {
  if (!Number.isFinite(value)) {
    return JSON.stringify(Number.isNaN(value) ? 'NaN' : value > 0 ? 'Infinity' : '-Infinity')
  }
  if (Number.isInteger(value) && Math.abs(value) < JS_SAFE_INTEGER_LIMIT) {
    // `value + 0` collapses -0 to 0 so it matches Dart's canonical form.
    return (value + 0).toString()
  }
  return value.toString()
}

function write(value: unknown, seen: object[]): string {
  if (value === null) return 'null'
  switch (typeof value) {
    case 'boolean':
      return value ? 'true' : 'false'
    case 'number':
      return canonicalNumber(value)
    case 'string':
      return JSON.stringify(value)
    case 'undefined':
      throw new Error('Cannot canonicalize undefined; use null')
    case 'object':
      break
    default:
      throw new Error(`Cannot canonicalize ${typeof value}`)
  }

  const node = value as object
  if (seen.includes(node)) throw new Error('Cannot canonicalize a cyclic structure')
  const nextSeen = [...seen, node]

  if (Array.isArray(node)) {
    return `[${node.map((entry) => write(entry, nextSeen)).join(',')}]`
  }

  const entries = Object.entries(node as Record<string, unknown>)
    .filter(([, entryValue]) => entryValue !== undefined)
    .sort(([left], [right]) => (left < right ? -1 : left > right ? 1 : 0))
  const body = entries
    .map(([key, entryValue]) => `${JSON.stringify(key)}:${write(entryValue, nextSeen)}`)
    .join(',')
  return `{${body}}`
}
