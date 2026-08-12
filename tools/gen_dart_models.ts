/**
 * Generates the Dart row models in `packages/ik_content` from the TypeScript
 * interfaces in `src/game/data`, keeping those interfaces the single schema
 * source for both clients.
 *
 * Rows are modelled as typed wrappers over the parsed JSON map rather than as
 * copies: the database has spaced column names and dynamic shop entry fields, so
 * wrapping preserves exact fidelity and round-trips without loss.
 *
 *   node --experimental-strip-types tools/gen_dart_models.ts
 *   node --experimental-strip-types tools/gen_dart_models.ts --check
 */

import { readFileSync, writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
import ts from 'typescript'

const SOURCE_FILES = [
  'src/game/data/types.ts',
  'src/game/data/enemyTypes.ts',
  'src/game/data/projectTypes.ts',
  'src/game/data/recipeTypes.ts',
]

const OUTPUT_FILE = 'packages/ik_content/lib/src/generated/rows.dart'

/** Tables whose rows are untyped records on the TypeScript side too. */
const UNTYPED_TABLE_TYPE = 'Map<String, Object?>'

/** Must match `formatter.page_width` in analysis_options.yaml. */
const DART_PAGE_WIDTH = 100

/**
 * Reserved and built-in identifiers that cannot be used as Dart member names.
 * A colliding column gets a `Value` suffix instead of a bespoke rename.
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

interface FieldModel {
  column: string
  dartName: string
  dartType: string
  accessor: string
  docs: string[]
}

interface RowModel {
  interfaceName: string
  fields: FieldModel[]
  hasDynamicFields: boolean
  docs: string[]
}

interface TableModel {
  tableName: string
  rowInterface: string | null
}

function main(): void {
  const check = process.argv.includes('--check')
  const sources = SOURCE_FILES.map((path) =>
    ts.createSourceFile(
      path,
      readFileSync(resolve(process.cwd(), path), 'utf8'),
      ts.ScriptTarget.Latest,
      true,
    ),
  )

  const stringLikeAliases = collectStringLikeAliases(sources)
  const interfaces = collectInterfaces(sources)
  const database = interfaces.get('GameDatabase')
  if (!database) throw new Error('GameDatabase interface not found')

  const tables = readTables(database)
  const needed = orderedRowInterfaces(tables, interfaces)
  const rows = needed.map((name) => buildRowModel(interfaces.get(name)!, stringLikeAliases))
  const output = renderDart(rows, tables)

  const outputPath = resolve(process.cwd(), OUTPUT_FILE)
  if (check) {
    const existing = readFileSync(outputPath, 'utf8')
    if (existing !== output) {
      process.stderr.write(
        `${OUTPUT_FILE} is out of date with ${SOURCE_FILES.join(', ')}.\n` +
          'Run: npm run gen:dart\n',
      )
      process.exit(1)
    }
    process.stdout.write(`${OUTPUT_FILE} is up to date\n`)
    return
  }

  writeFileSync(outputPath, output, 'utf8')
  process.stdout.write(`Wrote ${OUTPUT_FILE} (${rows.length} row models, ${tables.length} tables)\n`)
}

function collectInterfaces(sources: ts.SourceFile[]): Map<string, ts.InterfaceDeclaration> {
  const interfaces = new Map<string, ts.InterfaceDeclaration>()
  for (const source of sources) {
    for (const statement of source.statements) {
      if (ts.isInterfaceDeclaration(statement)) {
        interfaces.set(statement.name.text, statement)
      }
    }
  }
  return interfaces
}

/** Type aliases that are unions of string literals, so they map to Dart String. */
function collectStringLikeAliases(sources: ts.SourceFile[]): Set<string> {
  const aliases = new Set<string>()
  for (const source of sources) {
    for (const statement of source.statements) {
      if (!ts.isTypeAliasDeclaration(statement)) continue
      const node = statement.type
      const members = ts.isUnionTypeNode(node) ? node.types : [node]
      const allStrings = members.every(
        (member) =>
          member.kind === ts.SyntaxKind.StringKeyword ||
          (ts.isLiteralTypeNode(member) && ts.isStringLiteral(member.literal)),
      )
      if (allStrings) aliases.add(statement.name.text)
    }
  }
  return aliases
}

function readTables(database: ts.InterfaceDeclaration): TableModel[] {
  const tables: TableModel[] = []
  for (const member of database.members) {
    if (!ts.isPropertySignature(member) || !member.type) continue
    const tableName = propertyName(member)
    const type = member.type
    if (!ts.isArrayTypeNode(type)) {
      throw new Error(`GameDatabase.${tableName} must be an array type`)
    }
    const element = type.elementType
    if (ts.isTypeReferenceNode(element) && ts.isIdentifier(element.typeName)) {
      const referenced = element.typeName.text
      // Record<string, unknown> rows stay untyped, matching TypeScript.
      tables.push({ tableName, rowInterface: referenced === 'Record' ? null : referenced })
      continue
    }
    tables.push({ tableName, rowInterface: null })
  }
  return tables
}

function orderedRowInterfaces(
  tables: TableModel[],
  interfaces: Map<string, ts.InterfaceDeclaration>,
): string[] {
  const names: string[] = []
  for (const table of tables) {
    const name = table.rowInterface
    if (!name || names.includes(name)) continue
    if (!interfaces.has(name)) throw new Error(`Row interface not found: ${name}`)
    names.push(name)
  }
  return names.sort((a, b) => (a < b ? -1 : a > b ? 1 : 0))
}

function buildRowModel(
  declaration: ts.InterfaceDeclaration,
  stringLikeAliases: Set<string>,
): RowModel {
  const fields: FieldModel[] = []
  let hasDynamicFields = false
  const seen = new Set<string>()

  for (const member of declaration.members) {
    if (ts.isIndexSignatureDeclaration(member)) {
      hasDynamicFields = true
      continue
    }
    if (!ts.isPropertySignature(member) || !member.type) continue

    const column = propertyName(member)
    const dartName = uniqueDartName(column, seen)
    const { dartType, accessor } = mapType(member.type, member.questionToken != null, {
      column,
      interfaceName: declaration.name.text,
      stringLikeAliases,
    })
    fields.push({ column, dartName, dartType, accessor, docs: docLines(member) })
  }

  return {
    interfaceName: declaration.name.text,
    fields,
    hasDynamicFields,
    docs: docLines(declaration),
  }
}

function propertyName(member: ts.PropertySignature): string {
  const name = member.name
  if (ts.isIdentifier(name)) return name.text
  if (ts.isStringLiteral(name)) return name.text
  throw new Error(`Unsupported property name: ${name.getText()}`)
}

interface MapTypeContext {
  column: string
  interfaceName: string
  stringLikeAliases: Set<string>
}

function mapType(
  node: ts.TypeNode,
  optional: boolean,
  context: MapTypeContext,
): { dartType: string; accessor: string } {
  const members = ts.isUnionTypeNode(node) ? [...node.types] : [node]
  let nullable = optional
  const concrete: ts.TypeNode[] = []

  for (const member of members) {
    if (member.kind === ts.SyntaxKind.NullKeyword) {
      nullable = true
      continue
    }
    if (ts.isLiteralTypeNode(member) && member.literal.kind === ts.SyntaxKind.NullKeyword) {
      nullable = true
      continue
    }
    if (member.kind === ts.SyntaxKind.UndefinedKeyword) {
      nullable = true
      continue
    }
    concrete.push(member)
  }

  const kinds = new Set(concrete.map((member) => scalarKind(member, context)))
  if (kinds.size === 0) return { dartType: 'Object?', accessor: 'anyOrNull' }
  if (kinds.size > 1) {
    // Mixed scalar unions (config values, requirement references) stay dynamic,
    // exactly as they are in TypeScript.
    return { dartType: 'Object?', accessor: 'anyOrNull' }
  }

  const kind = [...kinds][0]!
  switch (kind) {
    case 'string':
      return nullable
        ? { dartType: 'String?', accessor: 'stringOrNull' }
        : { dartType: 'String', accessor: 'stringValue' }
    case 'number':
      return nullable
        ? { dartType: 'num?', accessor: 'numberOrNull' }
        : { dartType: 'num', accessor: 'numberValue' }
    case 'boolean':
      return nullable
        ? { dartType: 'bool?', accessor: 'boolOrNull' }
        : { dartType: 'bool', accessor: 'boolValue' }
    default:
      return { dartType: 'Object?', accessor: 'anyOrNull' }
  }
}

type ScalarKind = 'string' | 'number' | 'boolean' | 'unknown'

function scalarKind(node: ts.TypeNode, context: MapTypeContext): ScalarKind {
  switch (node.kind) {
    case ts.SyntaxKind.StringKeyword:
      return 'string'
    case ts.SyntaxKind.NumberKeyword:
      return 'number'
    case ts.SyntaxKind.BooleanKeyword:
      return 'boolean'
    default:
      break
  }
  if (ts.isLiteralTypeNode(node)) {
    if (ts.isStringLiteral(node.literal)) return 'string'
    if (ts.isNumericLiteral(node.literal)) return 'number'
    if (
      node.literal.kind === ts.SyntaxKind.TrueKeyword ||
      node.literal.kind === ts.SyntaxKind.FalseKeyword
    ) {
      return 'boolean'
    }
  }
  if (ts.isTypeReferenceNode(node) && ts.isIdentifier(node.typeName)) {
    if (context.stringLikeAliases.has(node.typeName.text)) return 'string'
  }
  throw new Error(
    `Unsupported type for ${context.interfaceName}["${context.column}"]: ${node.getText()}`,
  )
}

function uniqueDartName(column: string, seen: Set<string>): string {
  const name = toDartName(column)
  if (seen.has(name)) throw new Error(`Duplicate Dart field name "${name}" from column "${column}"`)
  seen.add(name)
  return name
}

/**
 * Table names are single PascalCase words, so they need splitting on case
 * boundaries as well. `NPCs` is the one name this cannot infer.
 */
const NAME_OVERRIDES: Record<string, string> = { NPCs: 'npcs' }

/** Splits `RewardEntries` into `Reward`, `Entries` and `XPCurve` into `XP`, `Curve`. */
function splitCamelCase(token: string): string[] {
  return token.match(/[A-Z]+(?![a-z])|[A-Z][a-z0-9]*|[a-z0-9]+/g) ?? [token]
}

export function toDartName(column: string): string {
  const override = NAME_OVERRIDES[column]
  if (override) return override

  const tokens = column
    .replace(/%/g, ' percent ')
    .split(/[^A-Za-z0-9]+/)
    .filter(Boolean)
    .flatMap(splitCamelCase)
  if (tokens.length === 0) throw new Error(`Column produced no identifier: "${column}"`)

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

function docLines(node: ts.Node): string[] {
  const source = node.getSourceFile()
  const ranges = ts.getLeadingCommentRanges(source.text, node.pos) ?? []
  const lines: string[] = []
  for (const range of ranges) {
    const text = source.text.slice(range.pos, range.end)
    if (!text.startsWith('/**')) continue
    for (const raw of text.split('\n')) {
      const cleaned = raw
        .replace(/^\s*\/\*\*+/, '')
        .replace(/\*+\/\s*$/, '')
        .replace(/^\s*\*ual?/, '')
        .replace(/^\s*\*\s?/, '')
        .trim()
      if (cleaned.length > 0) lines.push(cleaned)
    }
  }
  return lines
}

function renderDart(rows: RowModel[], tables: TableModel[]): string {
  const out: string[] = []
  out.push('// GENERATED FILE - DO NOT EDIT.')
  out.push('//')
  out.push('// Generated from:')
  for (const path of SOURCE_FILES) out.push(`//   ${path}`)
  out.push('//')
  out.push('// Regenerate with: npm run gen:dart')
  out.push('')
  out.push("import '../db_row.dart';")
  out.push('')

  for (const row of rows) {
    out.push(...renderRow(row))
    out.push('')
  }

  out.push(...renderDatabase(tables))
  return `${out.join('\n')}\n`
}

function renderRow(row: RowModel): string[] {
  const out: string[] = []
  for (const line of row.docs) out.push(`/// ${line}`)
  if (row.hasDynamicFields) {
    if (row.docs.length > 0) out.push('///')
    out.push('/// Carries extra columns beyond the typed accessors; read them from [raw].')
  }
  out.push(`class ${row.interfaceName} extends DbRow {`)
  out.push(`  const ${row.interfaceName}(super.raw);`)
  out.push('')
  for (const [index, field] of row.fields.entries()) {
    if (index > 0) out.push('')
    for (const line of field.docs) out.push(`  /// ${line}`)
    out.push(
      `  ${field.dartType} get ${field.dartName} => ${field.accessor}('${field.column}');`,
    )
  }
  out.push('}')
  return out
}

/**
 * Emits a class-level assignment of a call the way `dart format` would, so
 * generated output is already formatted and `--check` compares like for like.
 */
function assignment(head: string, callee: string, args: string[]): string[] {
  const single = `  ${head} = ${callee}(${args.join(', ')});`
  if (single.length <= DART_PAGE_WIDTH) return [single]
  return [`  ${head} = ${callee}(`, ...args.map((arg) => `    ${arg},`), '  );']
}

function renderDatabase(tables: TableModel[]): string[] {
  const out: string[] = []
  out.push('/// Table names in database order, mirroring `DATABASE_TABLES`.')
  out.push('const List<String> databaseTables = <String>[')
  for (const table of tables) out.push(`  '${table.tableName}',`)
  out.push('];')
  out.push('')
  out.push('/// Typed view over the parsed `game-database.json` root object.')
  out.push('///')
  out.push('/// Wraps [raw] without copying, so a filtered or reloaded database keeps the')
  out.push('/// exact JSON shape the TypeScript client sees.')
  out.push('class GameDatabase {')
  out.push('  GameDatabase(this.raw);')
  out.push('')
  out.push('  final Map<String, Object?> raw;')

  for (const table of tables) {
    const getter = toDartName(table.tableName)
    out.push('')
    if (table.rowInterface == null) {
      out.push(
        ...assignment(`late final List<${UNTYPED_TABLE_TYPE}> ${getter}`, 'untypedRows', [
          'raw',
          `'${table.tableName}'`,
        ]),
      )
      continue
    }
    out.push(
      ...assignment(`late final List<${table.rowInterface}> ${getter}`, 'typedRows', [
        'raw',
        `'${table.tableName}'`,
        `${table.rowInterface}.new`,
      ]),
    )
  }

  out.push('')
  out.push('  /// Raw row maps for [table], for code that works across tables.')
  out.push('  List<Map<String, Object?>> rowsOf(String table) => untypedRows(raw, table);')
  out.push('}')
  return out
}

main()
