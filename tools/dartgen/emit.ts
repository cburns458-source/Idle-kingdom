import { execFileSync } from 'node:child_process'
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'

export function generatedHeader(sources: string[]): string[] {
  const out = ['// GENERATED FILE - DO NOT EDIT.', '//', '// Generated from:']
  for (const path of sources) out.push(`//   ${path}`)
  out.push('//')
  out.push('// Regenerate with: npm run gen:dart')
  out.push('')
  return out
}

export function docComment(lines: string[], indent = ''): string[] {
  return lines.map((line) => `${indent}/// ${line}`)
}

/**
 * Runs the emitted source through `dart format` so generated files match what
 * CI's format check expects. Emitters can then stay naive about line breaks:
 * replicating the formatter's wrapping rules by hand was the fragile part.
 */
export function formatDart(source: string): string {
  const dir = mkdtempSync(join(tmpdir(), 'dartgen-'))
  const file = join(dir, 'generated.dart')
  try {
    writeFileSync(file, source, 'utf8')
    // The temp file sits outside the repo, so the page width from
    // analysis_options.yaml has to be passed explicitly.
    execFileSync('dart', ['format', `--page-width=${dartPageWidth()}`, file], { stdio: 'pipe' })
    return readFileSync(file, 'utf8')
  } catch (error) {
    if ((error as { code?: string }).code === 'ENOENT') {
      throw new Error('`dart` is required to generate Dart models; add the Dart SDK to PATH')
    }
    throw error
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
}

let cachedPageWidth: number | undefined

/** Reads `formatter.page_width` so generated output matches CI's format check. */
function dartPageWidth(): number {
  if (cachedPageWidth != null) return cachedPageWidth
  const options = readFileSync(resolve(process.cwd(), 'analysis_options.yaml'), 'utf8')
  const match = /^\s*page_width:\s*(\d+)/m.exec(options)
  if (!match) throw new Error('formatter.page_width not found in analysis_options.yaml')
  cachedPageWidth = Number(match[1])
  return cachedPageWidth
}
