import ts from 'typescript'
import { docComment, formatDart, generatedHeader } from './emit.ts'
import { toDartName } from './naming.ts'
import { docLines, propertyName, scalarKind, unwrapNullable, type ParsedSources } from './parse.ts'

/** Tables whose rows are untyped records on the TypeScript side too. */
const UNTYPED_TABLE_TYPE = 'Map<String, Object?>'

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

/**
 * Emits row models as typed wrappers over the parsed JSON map.
 *
 * The database has spaced column names and shops carry dynamic `Entry N ...`
 * columns, so wrapping preserves exact fidelity and round-trips without loss.
 */
export function renderRows(parsed: ParsedSources, sources: string[]): string {
  const database = parsed.interfaces.get('GameDatabase')
  if (!database) throw new Error('GameDatabase interface not found')

  const tables = readTables(database)
  const rowInterfaces = orderedRowInterfaces(tables, parsed)
  const rows = rowInterfaces.map((name) => buildRowModel(parsed.interfaces.get(name)!, parsed))

  const out = [...generatedHeader(sources), "import '../db_row.dart';", '']
  for (const row of rows) {
    out.push(...renderRow(row), '')
  }
  out.push(...renderDatabase(tables))
  return formatDart(`${out.join('\n')}\n`)
}

function readTables(database: ts.InterfaceDeclaration): TableModel[] {
  const tables: TableModel[] = []
  for (const member of database.members) {
    if (!ts.isPropertySignature(member) || !member.type) continue
    const tableName = propertyName(member)
    if (!ts.isArrayTypeNode(member.type)) {
      throw new Error(`GameDatabase.${tableName} must be an array type`)
    }
    const element = member.type.elementType
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

function orderedRowInterfaces(tables: TableModel[], parsed: ParsedSources): string[] {
  const names: string[] = []
  for (const table of tables) {
    const name = table.rowInterface
    if (!name || names.includes(name)) continue
    if (!parsed.interfaces.has(name)) throw new Error(`Row interface not found: ${name}`)
    names.push(name)
  }
  return names.sort((a, b) => (a < b ? -1 : a > b ? 1 : 0))
}

function buildRowModel(declaration: ts.InterfaceDeclaration, parsed: ParsedSources): RowModel {
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
    const dartName = toDartName(column)
    if (seen.has(dartName)) {
      throw new Error(`Duplicate Dart name "${dartName}" from column "${column}"`)
    }
    seen.add(dartName)

    fields.push({
      column,
      dartName,
      docs: docLines(member),
      ...accessorFor(member, column, declaration.name.text, parsed),
    })
  }

  return {
    interfaceName: declaration.name.text,
    fields,
    hasDynamicFields,
    docs: docLines(declaration),
  }
}

function accessorFor(
  member: ts.PropertySignature,
  column: string,
  interfaceName: string,
  parsed: ParsedSources,
): { dartType: string; accessor: string } {
  const { concrete, nullable } = unwrapNullable(member.type!, member.questionToken != null)
  const kinds = new Set(concrete.map((node) => scalarKind(node, parsed.stringLikeAliases)))

  if (kinds.size !== 1 || kinds.has('other')) {
    if (kinds.size === 1 && kinds.has('other')) {
      throw new Error(
        `Unsupported row column type for ${interfaceName}["${column}"]: ${member.type!.getText()}`,
      )
    }
    // Mixed scalar unions (config values, requirement references) stay dynamic,
    // exactly as they are in TypeScript.
    return { dartType: 'Object?', accessor: 'anyOrNull' }
  }

  switch ([...kinds][0]) {
    case 'string':
      return nullable
        ? { dartType: 'String?', accessor: 'stringOrNull' }
        : { dartType: 'String', accessor: 'stringValue' }
    case 'number':
      return nullable
        ? { dartType: 'num?', accessor: 'numberOrNull' }
        : { dartType: 'num', accessor: 'numberValue' }
    default:
      return nullable
        ? { dartType: 'bool?', accessor: 'boolOrNull' }
        : { dartType: 'bool', accessor: 'boolValue' }
  }
}

function renderRow(row: RowModel): string[] {
  const out = docComment(row.docs)
  if (row.hasDynamicFields) {
    if (row.docs.length > 0) out.push('///')
    out.push('/// Carries extra columns beyond the typed accessors; read them from [raw].')
  }
  out.push(`class ${row.interfaceName} extends DbRow {`)
  out.push(`  const ${row.interfaceName}(super.raw);`)
  for (const field of row.fields) {
    out.push('')
    out.push(...docComment(field.docs, '  '))
    out.push(`  ${field.dartType} get ${field.dartName} => ${field.accessor}('${field.column}');`)
  }
  out.push('}')
  return out
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
        `  late final List<${UNTYPED_TABLE_TYPE}> ${getter} = ` +
          `untypedRows(raw, '${table.tableName}');`,
      )
      continue
    }
    out.push(
      `  late final List<${table.rowInterface}> ${getter} = ` +
        `typedRows(raw, '${table.tableName}', ${table.rowInterface}.new);`,
    )
  }

  out.push('')
  out.push('  /// Raw row maps for [table], for code that works across tables.')
  out.push('  List<Map<String, Object?>> rowsOf(String table) => untypedRows(raw, table);')
  out.push('}')
  return out
}
