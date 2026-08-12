# Flutter/Dart migration

The React app in `src/` and the Dart client in `packages/` (plus `app_flutter/`,
added in a later phase) coexist during the migration. Both read the same content
from `content/`, and the Dart rules are validated against the TypeScript rules by
a fixture-replay harness rather than by hand.

## Layout

| Path | Role |
| --- | --- |
| `content/data`, `content/assets` | Canonical game data and art. Served by Vite (`publicDir: 'content'`) and bundled by Flutter. |
| `packages/ik_content` | Dart row models, database loading, validation, lookup indexes. |
| `packages/ik_rules` | Pure Dart port of `src/game`. No IO, no Flutter, no ambient clock or RNG. |
| `packages/ik_runtime` | Headless session: owns the save, advances ticks, defines storage and multiplayer ports. |
| `packages/ik_parity` | Test-only harness: canonical JSON, fixture replay, package purity guards. |
| `parity/fixtures` | Committed scenario recordings produced from the TypeScript rules. |
| `src/parity` | Scenario registry and the recorder/drift test. |

## Schema codegen

Row models in `packages/ik_content/lib/src/generated/rows.dart` are generated
from the TypeScript interfaces in `src/game/data`, so those interfaces stay the
single schema source. Adding a column is a one-file edit followed by:

```bash
npm run gen:dart
```

`npm run gen:dart:check` runs in CI and fails when the committed Dart drifts.

A row is a typed wrapper over the parsed JSON map, not a copy. The database uses
spaced column names (`'Skill ID'`) and shops carry dynamic `Entry N ...` columns,
so wrapping keeps unknown columns intact and lets a row round-trip byte for byte.
Numeric columns are typed `num` rather than `int` or `double`, because a JSON
number is neither on the TypeScript side.

## Parity workflow

Porting a module means making its recorded fixtures replay green in Dart.

1. Add scenarios for the module under `src/parity/scenarios/` and register them
   in `src/parity/scenarios/index.ts`. Inputs must be JSON so Dart can rebuild
   the exact same call; randomness comes from `mulberry32(seed)` and time is
   always an explicit `nowMs`.
2. Record them:

```bash
npm run parity:record
```

3. Port the module to Dart and replay the fixtures:

```bash
dart test packages/ik_rules
```

`npm test` re-derives every fixture and fails on drift, so a TypeScript change
that alters behavior is caught immediately. When the change is intentional,
re-record and re-run the Dart suite in the same commit.

## Determinism rules

These exist because the two languages disagree in ways that are easy to miss:

- **Randomness** is injected. `mulberry32` is implemented in both languages with
  identical 32-bit arithmetic; the Dart version splits multiplies into 16-bit
  halves so it also holds on Flutter Web, where an `int` is a JavaScript number.
- **Time** is a parameter. Dart ports take a required `nowMs` instead of
  defaulting to `Date.now()`.
- **Numbers** are compared through `canonicalJson`. Dart separates `int` from
  `double` where JavaScript has one type, so `1` and `1.0` encode identically
  while `1` and `1.0000001` do not.
- **Absent is not null.** The recorder omits `undefined` fields, matching
  `JSON.stringify`, so a Dart `toJson` must omit them too rather than writing
  `null`.

## Porting status

| Area | State |
| --- | --- |
| Parity harness, shared PRNG, CI | Done |
| `src/game/data` (models, loading, validation, indexes) | Done |
| Core rules (skills, xp, inventory, equipment, requirements, races) | Not started |
| Activity, production, recipes, projects | Not started |
| Combat, loot, potions, spells, critters, quests, achievements, cosmetics, world, bounties, bazaar | Not started |
| Save, migrations, unattended progress | Not started |
| Headless session runtime (extracted from `src/App.tsx`) | Not started |
| Flutter UI | Not started |
| Multiplayer backends | Not started |

## Commands

```bash
npm test                  # React app tests + parity fixture drift check
npm run parity:record     # Re-record fixtures from the TypeScript rules
npm run gen:dart          # Regenerate Dart row models from the TypeScript types
dart pub get              # Resolve the pub workspace
dart analyze              # Analyze every Dart package
dart format packages      # Format (page width 100, set in analysis_options.yaml)
dart test packages        # Every Dart package, including parity replay
```
