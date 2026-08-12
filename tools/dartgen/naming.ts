/**
 * Reserved and built-in identifiers that cannot be used as Dart member names.
 * A colliding name gets a `Value` suffix instead of a bespoke rename.
 */
const DART_KEYWORDS = new Set([
  'abstract', 'as', 'assert', 'async', 'await', 'base', 'break', 'case', 'catch', 'class', 'const',
  'continue', 'covariant', 'default', 'deferred', 'do', 'dynamic', 'else', 'enum', 'export',
  'extends', 'extension', 'external', 'factory', 'false', 'final', 'finally', 'for', 'function',
  'get', 'hide', 'if', 'implements', 'import', 'in', 'interface', 'is', 'late', 'library', 'mixin',
  'new', 'null', 'on', 'operator', 'part', 'required', 'rethrow', 'return', 'sealed', 'set', 'show',
  'static', 'super', 'switch', 'sync', 'this', 'throw', 'true', 'try', 'type', 'typedef', 'var',
  'void', 'when', 'while', 'with', 'yield',
])

/**
 * Names that cannot be inferred from their source spelling. `NPCs` would
 * otherwise split into `NP` and `Cs`.
 */
const NAME_OVERRIDES: Record<string, string> = { NPCs: 'npcs' }

/** Splits `RewardEntries` into `Reward`, `Entries` and `XPCurve` into `XP`, `Curve`. */
function splitCamelCase(token: string): string[] {
  return token.match(/[A-Z]+(?![a-z])|[A-Z][a-z0-9]*|[a-z0-9]+/g) ?? [token]
}

/** Converts a database column or table name into a Dart member name. */
export function toDartName(source: string): string {
  const override = NAME_OVERRIDES[source]
  if (override) return override

  const tokens = source
    .replace(/%/g, ' percent ')
    .split(/[^A-Za-z0-9]+/)
    .filter(Boolean)
    .flatMap(splitCamelCase)
  if (tokens.length === 0) throw new Error(`Name produced no identifier: "${source}"`)

  const parts = tokens.map((token, index) => {
    const lower = token.toLowerCase()
    if (index === 0) return lower
    if (/^[0-9]+$/.test(token)) return token
    return lower.charAt(0).toUpperCase() + lower.slice(1)
  })

  const joined = parts.join('')
  const name = /^[0-9]/.test(joined) ? `field${joined}` : joined
  return DART_KEYWORDS.has(name) ? `${name}Value` : name
}

/** Converts `SAVE_STORAGE_KEY` into `saveStorageKey`. */
export function constantToDartName(source: string): string {
  return toDartName(source.toLowerCase().replace(/_/g, ' '))
}
