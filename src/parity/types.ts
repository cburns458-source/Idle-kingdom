/** JSON-compatible values, the only currency parity fixtures deal in. */
export type JsonValue = null | boolean | number | string | JsonValue[] | { [key: string]: JsonValue }

/**
 * One recorded scenario.
 *
 * `input` is written to the fixture verbatim so the Dart replay can rebuild the
 * exact same call, and `output` is produced by driving the real TypeScript
 * implementation. Anything not expressible as JSON does not belong here.
 */
export interface ParityScenario {
  /** Fixture directory, e.g. `rng` or `content/validate`. */
  readonly module: string
  /** File name within the module directory, without extension. */
  readonly name: string
  readonly input: JsonValue
  readonly output: () => JsonValue
}

export function scenario(
  module: string,
  name: string,
  input: JsonValue,
  output: () => JsonValue,
): ParityScenario {
  return { module, name, input, output }
}
