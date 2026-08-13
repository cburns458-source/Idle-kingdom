# Flutter/Dart migration

The React app in `src/` and the Flutter client in `app_flutter/` (over the Dart
packages in `packages/`) coexist during the migration. Both read the same content
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
| `app_flutter` | The Flutter client. UI only: no rules, no derived numbers. |
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
dart test packages/ik_rules packages/ik_runtime
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
| Core rules (skills, xp, inventory, equipment, requirements, races) | Done |
| Activity, production, recipes, projects | Done |
| Combat, loot, potions, spells, critters, quests, achievements, cosmetics, world, bounties | Done |
| Save, migrations, unattended progress | Done |
| Headless session runtime (tick, events, travel, storage port) | Done |
| Bazaar and multiplayer backends | Not started |
| Flutter shell (theme, HUD, nav, location, map, skills, inventory) | Done |
| Remaining Flutter panels (shops, equipment, quests, bounties, wardrobe, …) | In progress |

## Save handling

Migrations are the one place the rules touch loose JSON. A version 1 save has
none of the fields the generated `PlayerSave` requires, so `migrateSaveJson`
works on the decoded map and only the finished save is read through the model —
which is also what proves the chain produces something the schema can load.

Storage itself is a port, not a rule. `ik_rules` owns `createNewSave`,
`parseSave`, and `touchSave`; `ik_runtime`'s `SaveRepository` adds the read /
write / clear cycle over a `SaveStorage` the host implements (`localStorage` in
the React app, `shared_preferences` or IndexedDB under Flutter).

## The session tick

`advanceSession(db, save, nowMs, random)` advances whatever the save has due at
`nowMs` — one combat round, one gathering action, one craft, a death-pause
recovery, or the next action for an activity that has none — and returns the new
save plus the events the client should react to. It is the only thing a client
loop has to call: React drives it from a single animation frame callback, and the
unattended resolver is the same rules run over a past window.

Events (`SessionEvent`) are what keeps presentation out of the rules. A tick says
`enemy-defeated` or `craft-completed`; whether that is a flash, a toast, or a
sound is the client's business. Combat rewards are applied in the tick that
resolves the round rather than after the defeat flash, so closing the game
mid-animation cannot lose a kill.

Both halves are recorded as scripted runs under `parity/fixtures/session/tick`:
each case ticks one save shape at pinned offsets — before the timer is due, the
tick that resolves it, and enough afterwards to see the follow-up — and compares
the events, the progress bar, and the whole save at every step.

Travel is the other thing a client would otherwise have to re-derive.
`planTravel` answers a travel request with `blocked`, `instant` (the arrival has
already happened), or `timed` (the activity is stopped and the client animates
the journey, then calls `arriveFromTravel`). Hostility is folded into the
arrival, so forced combat and its message arrive together.

`prepareSaveForWrite` is the one path to storage: it moves the unattended anchor
to the write time and catches achievements and statistics up. Boot is the single
exception, because the catch-up resolver has already set the anchor — and
deliberately leaves it short when a long absence ran out of steps.

`GameSession` (Dart only) holds those pieces together for the Flutter client: it
owns the save, boots it, ticks it, applies whatever a rules call returned, and
runs travel. Intents stay the rules functions themselves; the session is just
where their result lands, so nothing can skip the write pipeline.

## The Flutter client

`app_flutter` is a member of the same pub workspace as the packages, so it uses
`ik_content`, `ik_rules`, and `ik_runtime` by path with no publishing step.
`app_flutter/content` is a symlink to the repo's `content/`, which is how one copy
of the data and art reaches both clients; Flutter needs each asset directory
listed in `pubspec.yaml` individually, as the list is not recursive.

The layer that exists only here is `GameController`, a `ChangeNotifier` wrapped
around `GameSession`. It holds what is true of a screen and nothing else — the
last few reward lines, the current message, the journey being animated — and the
shell drives its `tick()` from a `Ticker`, so the loop stops when the app is
backgrounded and picks the elapsed time back up from the clock on return. Player
intents call the shared rules (`requestActivityStart`, `assignRace`, …) and hand
the result to `GameSession.apply`, which is the only way a save reaches storage.

Two rules keep the client honest, and both are worth stating because breaking
either is invisible until the two clients disagree:

- **No derived numbers in widgets.** A widget may format and lay out; anything
  computed comes from the packages. If a number is not available, the fix is a
  function in `ik_rules`, not arithmetic in `build`.
- **No ambient clock.** Time is read through `session.clock()`, never
  `DateTime.now()`, so a widget test drives the game by moving a fake clock
  instead of waiting on real frames.

Widget tests build the shell over a `MemorySaveStorage` and a controllable clock,
which is enough to play: create a character, start and stop an activity, travel,
and watch an action pay out.

## Commands

```bash
npm test                  # React app tests + parity fixture drift check
npm run parity:record     # Re-record fixtures from the TypeScript rules
npm run gen:dart          # Regenerate Dart row models from the TypeScript types
dart pub get              # Resolve the pub workspace
dart analyze              # Analyze every Dart package
dart format packages      # Format (page width 100, set in analysis_options.yaml)
dart test packages        # Every Dart package, including parity replay

cd app_flutter
flutter test              # Widget tests over a fake clock and in-memory storage
flutter run -d chrome     # The client, reading the shared content/
```
