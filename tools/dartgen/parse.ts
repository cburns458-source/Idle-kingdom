import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import ts from 'typescript'

export interface ParsedSources {
  files: ts.SourceFile[]
  interfaces: Map<string, ts.InterfaceDeclaration>
  /** Type aliases that are unions of string literals, so they map to Dart String. */
  stringLikeAliases: Set<string>
}

export function parseSources(paths: string[]): ParsedSources {
  const files = paths.map((path) =>
    ts.createSourceFile(
      path,
      readFileSync(resolve(process.cwd(), path), 'utf8'),
      ts.ScriptTarget.Latest,
      true,
    ),
  )

  const interfaces = new Map<string, ts.InterfaceDeclaration>()
  const stringLikeAliases = new Set<string>()

  for (const file of files) {
    for (const statement of file.statements) {
      if (ts.isInterfaceDeclaration(statement)) {
        interfaces.set(statement.name.text, statement)
        continue
      }
      if (ts.isTypeAliasDeclaration(statement) && isStringLikeAlias(statement.type)) {
        stringLikeAliases.add(statement.name.text)
      }
    }
  }

  return { files, interfaces, stringLikeAliases }
}

function isStringLikeAlias(node: ts.TypeNode): boolean {
  const members = ts.isUnionTypeNode(node) ? node.types : [node]
  return members.every(
    (member) =>
      member.kind === ts.SyntaxKind.StringKeyword ||
      (ts.isLiteralTypeNode(member) && ts.isStringLiteral(member.literal)),
  )
}

export function propertyName(member: ts.PropertySignature): string {
  const name = member.name
  if (ts.isIdentifier(name)) return name.text
  if (ts.isStringLiteral(name)) return name.text
  throw new Error(`Unsupported property name: ${name.getText()}`)
}

/** Doc comment lines attached to a declaration, without the comment markers. */
export function docLines(node: ts.Node): string[] {
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
        .replace(/^\s*\*\s?/, '')
        .trim()
      if (cleaned.length > 0) lines.push(cleaned)
    }
  }
  return lines
}

export interface UnwrappedType {
  /** Union members with `null` and `undefined` removed. */
  concrete: ts.TypeNode[]
  nullable: boolean
}

/** Splits a type into its non-null members plus whether null is allowed. */
export function unwrapNullable(node: ts.TypeNode, optional: boolean): UnwrappedType {
  const members = ts.isUnionTypeNode(node) ? [...node.types] : [node]
  let nullable = optional
  const concrete: ts.TypeNode[] = []

  for (const member of members) {
    if (
      member.kind === ts.SyntaxKind.NullKeyword ||
      member.kind === ts.SyntaxKind.UndefinedKeyword ||
      (ts.isLiteralTypeNode(member) && member.literal.kind === ts.SyntaxKind.NullKeyword)
    ) {
      nullable = true
      continue
    }
    concrete.push(member)
  }

  return { concrete, nullable }
}

export type ScalarKind = 'string' | 'number' | 'boolean' | 'other'

export function scalarKind(node: ts.TypeNode, stringLikeAliases: Set<string>): ScalarKind {
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
  if (
    ts.isTypeReferenceNode(node) &&
    ts.isIdentifier(node.typeName) &&
    stringLikeAliases.has(node.typeName.text)
  ) {
    return 'string'
  }
  return 'other'
}

/** Reads `export const NAME = <literal>` declarations, including string arrays. */
export function collectConstants(
  file: ts.SourceFile,
): Array<{ name: string; dartType: string; value: string; docs: string[] }> {
  const constants: Array<{ name: string; dartType: string; value: string; docs: string[] }> = []

  for (const statement of file.statements) {
    if (!ts.isVariableStatement(statement)) continue
    const exported = statement.modifiers?.some(
      (modifier) => modifier.kind === ts.SyntaxKind.ExportKeyword,
    )
    if (!exported) continue

    for (const declaration of statement.declarationList.declarations) {
      if (!ts.isIdentifier(declaration.name) || !declaration.initializer) continue
      const literal = dartLiteral(declaration.initializer)
      if (!literal) continue
      constants.push({
        name: declaration.name.text,
        dartType: literal.dartType,
        value: literal.value,
        docs: docLines(statement),
      })
    }
  }

  return constants
}

function dartLiteral(node: ts.Expression): { dartType: string; value: string } | null {
  if (ts.isAsExpression(node)) return dartLiteral(node.expression)
  if (ts.isNumericLiteral(node)) {
    const text = node.text.replace(/_/g, '')
    return { dartType: Number.isInteger(Number(text)) ? 'int' : 'double', value: text }
  }
  if (ts.isStringLiteral(node)) {
    return { dartType: 'String', value: `'${node.text.replace(/'/g, "\\'")}'` }
  }
  if (node.kind === ts.SyntaxKind.TrueKeyword) return { dartType: 'bool', value: 'true' }
  if (node.kind === ts.SyntaxKind.FalseKeyword) return { dartType: 'bool', value: 'false' }
  if (ts.isArrayLiteralExpression(node)) {
    const values = node.elements.map((element) => dartLiteral(element))
    if (values.some((value) => value?.dartType !== 'String')) return null
    return {
      dartType: 'List<String>',
      value: `<String>[${values.map((value) => value!.value).join(', ')}]`,
    }
  }
  return null
}
