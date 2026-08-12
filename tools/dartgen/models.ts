import ts from 'typescript'
import { docComment, formatDart, generatedHeader } from './emit.ts'
import { constantToDartName, toDartName } from './naming.ts'
import {
  collectConstants,
  docLines,
  propertyName,
  scalarKind,
  unwrapNullable,
  type ParsedSources,
} from './parse.ts'

/** How a TypeScript field maps onto a Dart field plus its JSON conversions. */
interface DartFieldType {
  dartType: string
  nullable: boolean
  /** True for values that need no conversion in either direction. */
  isScalar: boolean
  fromJson: (jsonExpr: string) => string
  /** [access] is `.` or `?.` so nullable fields short-circuit. */
  toJson: (fieldExpr: string, access: string) => string
}

interface ModelField {
  jsonKey: string
  dartName: string
  type: DartFieldType
  /** Declared with `?`, so it is omitted from JSON when null. */
  optional: boolean
  docs: string[]
}

interface ModelClass {
  name: string
  fields: ModelField[]
  docs: string[]
}

/**
 * Emits immutable Dart data classes for the save schema.
 *
 * Unlike database rows, saves are constructed and rewritten constantly by the
 * rules, so real fields and a `copyWith` beat a map wrapper. Fields declared
 * optional in TypeScript are omitted from `toJson` when null, matching what
 * `JSON.stringify` writes.
 */
export function renderModels(
  parsed: ParsedSources,
  sources: string[],
  supportImport: string,
): string {
  const classes: ModelClass[] = []
  for (const [name, declaration] of parsed.interfaces) {
    if (hasFunctionMember(declaration)) continue
    classes.push(buildModel(name, declaration, parsed))
  }
  classes.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0))

  const constants = parsed.files.flatMap((file) => collectConstants(file))

  const out = [...generatedHeader(sources), `import '${supportImport}';`, '']

  for (const constant of constants) {
    out.push(...docComment(constant.docs))
    out.push(`const ${constant.dartType} ${constantToDartName(constant.name)} = ${constant.value};`)
    out.push('')
  }

  out.push('/// Distinguishes "leave unchanged" from "set to null" in copyWith.');
  out.push('const Object _unset = Object();')
  out.push('')

  for (const model of classes) {
    out.push(...renderModel(model), '')
  }

  return formatDart(`${out.join('\n').trimEnd()}\n`)
}

function hasFunctionMember(declaration: ts.InterfaceDeclaration): boolean {
  return declaration.members.some(
    (member) =>
      ts.isMethodSignature(member) ||
      (ts.isPropertySignature(member) &&
        member.type != null &&
        ts.isFunctionTypeNode(member.type)),
  )
}

function buildModel(
  name: string,
  declaration: ts.InterfaceDeclaration,
  parsed: ParsedSources,
): ModelClass {
  const fields: ModelField[] = []
  for (const member of declaration.members) {
    if (!ts.isPropertySignature(member) || !member.type) continue
    const jsonKey = propertyName(member)
    const optional = member.questionToken != null
    fields.push({
      jsonKey,
      dartName: toDartName(jsonKey),
      optional,
      docs: docLines(member),
      type: mapType(member.type, optional, parsed, `${name}.${jsonKey}`),
    })
  }
  return { name, fields, docs: docLines(declaration) }
}

function mapType(
  node: ts.TypeNode,
  optional: boolean,
  parsed: ParsedSources,
  context: string,
): DartFieldType {
  const { concrete, nullable } = unwrapNullable(node, optional)
  if (concrete.length === 0) return dynamicType(nullable)

  const kinds = new Set(concrete.map((member) => scalarKind(member, parsed.stringLikeAliases)))
  if (kinds.size > 1) return dynamicType(nullable)

  const kind = [...kinds][0]!
  if (kind !== 'other') return scalarType(kind, nullable)
  if (concrete.length > 1) {
    throw new Error(`Unsupported union of structured types at ${context}: ${node.getText()}`)
  }
  return structuredType(concrete[0]!, nullable, parsed, context)
}

function dynamicType(nullable: boolean): DartFieldType {
  return {
    dartType: 'Object?',
    nullable,
    isScalar: true,
    fromJson: (json) => json,
    toJson: (field) => field,
  }
}

function scalarType(kind: 'string' | 'number' | 'boolean', nullable: boolean): DartFieldType {
  const base = kind === 'string' ? 'String' : kind === 'number' ? 'num' : 'bool';
  const dartType = nullable ? `${base}?` : base
  return {
    dartType,
    nullable,
    isScalar: true,
    fromJson: (json) => `${json} as ${dartType}`,
    toJson: (field) => field,
  }
}

function structuredType(
  node: ts.TypeNode,
  nullable: boolean,
  parsed: ParsedSources,
  context: string,
): DartFieldType {
  if (ts.isArrayTypeNode(node)) {
    return listType(node.elementType, nullable, parsed, context)
  }
  if (ts.isTypeReferenceNode(node) && ts.isIdentifier(node.typeName)) {
    const name = node.typeName.text
    const args = node.typeArguments ?? []
    if (name === 'Array' && args.length === 1) return listType(args[0]!, nullable, parsed, context)
    if (name === 'Record' && args.length === 2) return recordType(args[1]!, nullable, parsed, context)
    if (parsed.interfaces.has(name)) return classType(name, nullable)
  }
  if (ts.isTypeLiteralNode(node)) {
    throw new Error(
      `Inline object type at ${context}; give it a named interface so it can be generated`,
    )
  }
  throw new Error(`Unsupported type at ${context}: ${node.getText()}`)
}

function classType(name: string, nullable: boolean): DartFieldType {
  return {
    dartType: nullable ? `${name}?` : name,
    nullable,
    isScalar: false,
    fromJson: (json) =>
      nullable ? `mapOrNull(${json}, ${name}.fromJson)` : `${name}.fromJson(asJsonMap(${json}))`,
    toJson: (field, access) => `${field}${access}toJson()`,
  }
}

function listType(
  element: ts.TypeNode,
  nullable: boolean,
  parsed: ParsedSources,
  context: string,
): DartFieldType {
  const entry = mapType(element, false, parsed, `${context}[]`)
  const entryAccess = entry.nullable ? '?.' : '.'
  const dartType = nullable ? `List<${entry.dartType}>?` : `List<${entry.dartType}>`
  return {
    dartType,
    nullable,
    isScalar: false,
    fromJson: (json) => `listOf(${json}, (Object? entry) => ${entry.fromJson('entry')})`,
    toJson: (field, access) =>
      entry.isScalar
        ? field
        : `${field}${access}map((entry) => ${entry.toJson('entry', entryAccess)}).toList()`,
  }
}

function recordType(
  value: ts.TypeNode,
  nullable: boolean,
  parsed: ParsedSources,
  context: string,
): DartFieldType {
  const entry = mapType(value, false, parsed, `${context}{}`)
  const entryAccess = entry.nullable ? '?.' : '.'
  const dartType = nullable ? `Map<String, ${entry.dartType}>?` : `Map<String, ${entry.dartType}>`
  return {
    dartType,
    nullable,
    isScalar: false,
    fromJson: (json) => `mapOf(${json}, (Object? value) => ${entry.fromJson('value')})`,
    toJson: (field, access) =>
      entry.isScalar
        ? field
        : `${field}${access}map((key, value) => MapEntry(key, ${entry.toJson('value', entryAccess)}))`,
  }
}

function renderModel(model: ModelClass): string[] {
  const out = docComment(model.docs)
  out.push(`class ${model.name} {`)
  out.push(...renderConstructor(model))
  out.push('')
  out.push(...renderFromJson(model))
  for (const field of model.fields) {
    out.push('')
    out.push(...docComment(field.docs, '  '))
    out.push(`  final ${field.type.dartType} ${field.dartName};`)
  }
  out.push('')
  out.push(...renderToJson(model))
  out.push('')
  out.push(...renderCopyWith(model))
  out.push('}')
  return out
}

function renderConstructor(model: ModelClass): string[] {
  if (model.fields.length === 0) return [`  const ${model.name}();`]
  const params = model.fields.map((field) =>
    field.type.nullable ? `this.${field.dartName}` : `required this.${field.dartName}`,
  )
  return [`  const ${model.name}({${params.join(', ')}});`]
}

function renderFromJson(model: ModelClass): string[] {
  const out = [`  factory ${model.name}.fromJson(Map<String, Object?> json) {`]
  out.push(`    return ${model.name}(`)
  for (const field of model.fields) {
    out.push(`      ${field.dartName}: ${field.type.fromJson(`json['${field.jsonKey}']`)},`)
  }
  out.push('    );')
  out.push('  }')
  return out
}

function renderToJson(model: ModelClass): string[] {
  const out = ['  Map<String, Object?> toJson() {', '    return <String, Object?>{']
  for (const field of model.fields) {
    const access = field.type.nullable ? '?.' : '.'
    const value = field.type.toJson(field.dartName, access)
    // Optional fields are absent rather than null once JSON.stringify has run.
    const entry = field.optional
      ? `      if (${field.dartName} != null) '${field.jsonKey}': ${value},`
      : `      '${field.jsonKey}': ${value},`
    out.push(entry)
  }
  out.push('    };')
  out.push('  }')
  return out
}

function renderCopyWith(model: ModelClass): string[] {
  if (model.fields.length === 0) return [`  ${model.name} copyWith() => this;`]

  const out = [`  ${model.name} copyWith({`]
  for (const field of model.fields) {
    const type = field.type.nullable ? 'Object?' : `${field.type.dartType}?`
    const suffix = field.type.nullable ? ' = _unset' : ''
    out.push(`    ${type} ${field.dartName}${suffix},`)
  }
  out.push('  }) {')
  out.push(`    return ${model.name}(`)
  for (const field of model.fields) {
    const name = field.dartName
    const value = field.type.nullable
      ? `${name} == _unset ? this.${name} : ${name} as ${field.type.dartType}`
      : `${name} ?? this.${name}`
    out.push(`      ${name}: ${value},`)
  }
  out.push('    );')
  out.push('  }')
  return out
}
