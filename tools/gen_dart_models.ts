/**
 * Generates Dart models from the TypeScript type declarations, keeping those
 * declarations the single schema source for both clients.
 *
 *   npm run gen:dart          # write
 *   npm run gen:dart:check    # fail if the committed output has drifted
 */

import { readFileSync, writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { renderModels } from './dartgen/models.ts'
import { parseSources } from './dartgen/parse.ts'
import { renderRows } from './dartgen/rows.ts'

interface Target {
  label: string
  sources: string[]
  output: string
  render: (sources: string[], output: string) => string
}

const TARGETS: Target[] = [
  {
    label: 'database rows',
    sources: [
      'src/game/data/types.ts',
      'src/game/data/enemyTypes.ts',
      'src/game/data/projectTypes.ts',
      'src/game/data/recipeTypes.ts',
    ],
    output: 'packages/ik_content/lib/src/generated/rows.dart',
    render: (sources) => renderRows(parseSources(sources), sources),
  },
  {
    label: 'save models',
    sources: ['src/game/save/types.ts'],
    output: 'packages/ik_rules/lib/src/save/generated/save_models.dart',
    render: (sources) => renderModels(parseSources(sources), sources, '../../json_support.dart'),
  },
]

function main(): void {
  const check = process.argv.includes('--check')
  let drifted = false

  for (const target of TARGETS) {
    const rendered = target.render(target.sources, target.output)
    const path = resolve(process.cwd(), target.output)

    if (!check) {
      writeFileSync(path, rendered, 'utf8')
      process.stdout.write(`Wrote ${target.output} (${target.label})\n`)
      continue
    }

    const existing = readFileSync(path, 'utf8')
    if (existing === rendered) {
      process.stdout.write(`${target.output} is up to date\n`)
      continue
    }
    drifted = true
    process.stderr.write(
      `${target.output} is out of date with ${target.sources.join(', ')}.\n` +
        'Run: npm run gen:dart\n',
    )
  }

  if (drifted) process.exit(1)
}

main()
