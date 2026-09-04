# Flutter/Dart migration

The game is the Flutter client in `app_flutter/`, over the Dart packages in
`packages/`. The React app it replaced has been retired; what is left under
`src/` is the TypeScript rules the Dart port was recorded from, kept as the
parity reference, plus the harness that records them.

## Layout

| Path | Role |
| --- | --- |
| `content/data`, `content/assets` | Canonical game data and art. Bundled by Flutter, read from disk by the reference tests. |
| `packages/ik_content` | Dart row models, database loading, validation, lookup indexes. |
| `packages/ik_rules` | Pure Dart port of `src/game`. No IO, no Flutter, no ambient clock or RNG. |
| `packages/ik_runtime` | Headless session: owns the save, advances ticks, defines the storage port. |
| `packages/ik_net` | Port of `src/game/multiplayer`: the local backend, the remote one, and the view models the social screens read. No transport. |
| `packages/ik_parity` | Test-only harness: canonical JSON, fixture replay, package purity guards. |
| `app_flutter` | The Flutter client. UI only: no rules, no derived numbers. |
| `parity/fixtures` | Committed scenario recordings produced from the TypeScript rules. |
| `src/game` | The reference rules. Not shipped and not run by any client. |
| `src/parity` | Scenario registry and the recorder/drift test. |

## What is left of `src/`

The React client is gone: no `index.html`, no `src/ui`, no React dependencies,
and `vitest.config.ts` in place of a Vite app config. `src/game` stays because
the fixtures under `parity/fixtures` are recorded from it, and `npm test`
re-derives every one of them, which is what turns "the Dart port matches" into
something a machine checks. It is also still the schema source for
`npm run gen:dart`.

That makes `src/game` a reference, not a second implementation: a rule change
belongs in Dart, and the TypeScript is only touched when a fixture has to be
re-recorded to describe the new behavior. New rules that never existed in
TypeScript — `consolidateAwayMessages`, `importSaveText` — live in Dart alone,
with ordinary unit tests instead of fixtures. Once the fixtures are no longer
worth re-recording, `src/` and the npm toolchain can go entirely.

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
dart test packages
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
| Multiplayer: local backend, hosted backend, social view models | Done |
| Flutter shell (theme, HUD, nav, location, map, skills, inventory) | Done |
| Remaining Flutter panels (shops, equipment, quests, bounties, wardrobe, …) | Done |
| Asset audit, save transfer, retiring the React app | Done |

## Save handling

Migrations are the one place the rules touch loose JSON. A version 1 save has
none of the fields the generated `PlayerSave` requires, so `migrateSaveJson`
works on the decoded map and only the finished save is read through the model —
which is also what proves the chain produces something the schema can load.

Storage itself is a port, not a rule. `ik_rules` owns `createNewSave`,
`parseSave`, and `touchSave`; `ik_runtime`'s `SaveRepository` adds the read /
write / clear cycle over a `SaveStorage` the host implements, which under Flutter
is `shared_preferences`.

## The session tick

`advanceSession(db, save, nowMs, random)` advances whatever the save has due at
`nowMs` — one combat round, one gathering action, one craft, a death-pause
recovery, or the next action for an activity that has none — and returns the new
save plus the events the client should react to. It is the only thing a client
loop has to call — the shell drives it from a single frame callback — and the
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
`planTravel` answers a travel request with `blocked` or `instant` (the arrival
has already happened). A client may play a map-walk animation first; the save
only changes on `planTravel`. Hostility is folded into the arrival, so forced
combat and its message arrive together.

`prepareSaveForWrite` is the one path to storage: it moves the unattended anchor
to the write time and catches achievements and statistics up. Boot is the single
exception, because the catch-up resolver has already set the anchor — and
deliberately leaves it short when a long absence ran out of steps.

`GameSession` (Dart only) holds those pieces together for the Flutter client: it
owns the save, boots it, ticks it, applies whatever a rules call returned, and
runs travel. Intents stay the rules functions themselves; the session is just
where their result lands, so nothing can skip the write pipeline.

## Multiplayer

`ik_net` is the port of `src/game/multiplayer`, and it holds no sockets. Both
backends sit behind one `MultiplayerService`:

- **Local** keeps accounts, guilds, chat, presence, claims, and posts in a single
  JSON document in the same store as the save, so the social screens are playable
  and testable with no project configured. It is also the reference for what the
  hosted backend has to agree with.
- **Hosted** talks to Supabase through `RemoteTransport`, a narrow port the
  Flutter client implements over `supabase_flutter`. Keeping the rows, column
  names, and refusal messages in `remote.dart` (shared with `remote.ts`) means
  the two clients write the same tables, and a purity test keeps the package free
  of transport imports. Accounts, saves, boards, chat, and guilds go over the
  wire; presence, the Bazaar, bounty claims, and sparring partners stay on the
  device, the last because a fight reads another player's save and row-level
  security will not hand that over.

What a guild *means* is in `guild_rules.dart`, which both backends read: how a
name and tag are cleaned, why founding one is refused, what a rank change may
do, and what a donation pays for. The difference between them is only where the
answer is kept, and who settles a race — one device checks the table it owns, and
the server lets a unique index decide who got the name.

A social read answers with what arrived, so a screen short of one list still
draws the others. `NotedReads` wraps the transport and keeps the reason the first
read was refused, which `refresh` shows once. Without it a project missing a
migration is indistinguishable from a quiet game: an empty roster, an empty
board, and no button that appears to do anything.

What a social screen shows is a view model, not a widget's own reading of a
record: `views.ts` and `views.dart` derive the guild browser rows, the roster and
its rank options, the leaderboard rows, the nearby list, the public profile, and
the chat tabs, and the same fixtures replay in both languages. Guild emblems are
one SVG path table (`emblems.dart`), so a banner drawn in Flutter matches the one
drawn in the browser.

Two decisions are worth stating because they are player-visible:

- **Chat is local everywhere.** A channel is the location the player is standing
  in, whichever map or sub-map that is; the Citadel has no channel of its own.
  Global, guild, and direct tabs are the other three, and the unread count is a
  read cursor stored per account next to the save.
- **The Citadel Plaza is one panel with tabs.** Hourly bounties and the Grand
  Bazaar are boards opened from the Plaza the way a shop is, not separate
  screens. The hour's first turn-in is settled by whichever backend is in play —
  `turnInBounty` asks for the claim before it pays, so the race has one winner.

## The Flutter client

`app_flutter` is a member of the same pub workspace as the packages, so it uses
`ik_content`, `ik_rules`, `ik_runtime`, and `ik_net` by path with no publishing
step. `app_flutter/content` is a symlink to the repo's `content/`, which is how
the data and the art reach the bundle without a second copy.

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

`MultiplayerController` is the same idea for the social half: it holds who is
signed in, the guild in hand, the board last read, and who is nearby, and runs
presence and the unread count on timers that stop with the controller. Which
backend it wraps is decided once at boot — a build given Supabase credentials
gets the hosted service, anything else (or a project that cannot be reached) gets
the local one, because failing to connect must not stop the game starting.

Widget tests build the shell over a `MemorySaveStorage` and a controllable clock,
which is enough to play: create a character, start and stop an activity, travel,
and watch an action pay out. The social screens are tested the same way, over the
local backend or a transport held in memory, so no test needs a project.

## Art, and the audit that keeps it whole

Every path the client asks for is derived — an item's icon from its id, key,
category, and name; a location's background from its id — so a missing file is
invisible until the screen that needs it opens on a device. `asset_audit_test`
therefore walks the database and looks: every item, skill, slot, map, location,
enemy, gathering action, station, critter, and appearance choice must resolve to
a file that exists, and every id must be *named* by its art table rather than
answered with a fallback. It also parses the `assets:` list out of
`pubspec.yaml`, because Flutter's list is not recursive: a new art directory that
is not declared there simply will not be in the bundle, and nothing else would
say so.

The two exceptions are deliberate. A horizon gateway (`LOC-0019`, `LOC-0020`) is
browsed on the world map and never entered, so it has no background of its own,
and the fallbacks stay in the tables so an id nobody has drawn yet cannot crash a
screen. `content/assets/asset-manifest.json` is a record from the art passes that
generated the files; neither client reads it, and the tables in code are what
decide which file a row gets.

One thing the audit does not judge is weight, but the art is no longer the 62 MB
of 1024×1024 PNG it used to be. Sprites are lossless WebP; location and map
backgrounds are 384px lossy WebP in a low-detail pixel style, generated from the
original paintings except where those files were copies (town interiors, the
Citadel, the Queen's chamber, the abandoned mineshaft). Flutter draws them with
nearest-neighbour filtering so the pixels stay square.

## Bringing a save over

A save is text, and the text is the save JSON itself — byte for byte what storage
holds — which is what makes leaving the old client cheap. `exportSaveText` and
`importSaveText` (in `ik_runtime`) are the whole feature, and the account screen
offers them as *Copy save* and *Import save*, available signed in or not: the
cloud save above needs a backend, and this needs nothing.

Importing replaces the character on the device, so it asks first, and it goes
through `GameController.commit` like any other rules result rather than writing
storage itself. A pasted save is migrated on the way in, so a save from any older
version is readable.

The web build also adopts a save the React client left behind, once, when this
device has none of its own. `shared_preferences` namespaces its keys, so the old
value sits beside the new one instead of being found by it; `readLegacyBrowserSave`
reads the bare key through a conditional import that is a stub off the web, and
`adoptForeignSave` refuses to overwrite a character already being played here.
The old value is left in place afterwards, costing nothing and losing nothing.

## The release check

Fixtures prove a rule was ported; they do not prove the game can be played. The
release check is therefore a scripted playthrough (`packages/ik_runtime/test/
playthrough_test.dart`) that drives a real `GameSession` over the shipped
content: start a character, swear a race, travel, gather an action to its reward,
fight a round to its outcome, queue and finish a craft, reach a shop, and open
the game again to find the same save. Everything goes through the session rather
than the rules directly, so a step that computed the right answer and forgot to
store it fails here rather than on someone's phone.

Together with the asset audit, that is the whole of what "it works" means for a
release: the content validates, the art is all present, the loop pays out, and
the save survives a relaunch. CI runs both, plus `flutter build web`.

## Commands

```bash
npm test                  # The reference rules + parity fixture drift check
npm run parity:record     # Re-record fixtures from the TypeScript rules
npm run gen:dart          # Regenerate Dart row models from the TypeScript types
dart pub get              # Resolve the pub workspace
dart analyze              # Analyze every Dart package
dart format packages      # Format (page width 100, set in analysis_options.yaml)
dart test packages        # Every Dart package, including parity replay

cd app_flutter
flutter test              # Widget tests over a fake clock and in-memory storage
flutter build web         # What CI builds, and what a release ships
flutter run -d chrome     # The client, reading the shared content/

# From the repo root, the same as `flutter run` against the web-server device:
npm run dev               # Serves the Flutter client at http://localhost:5173

# The same client against a Supabase project instead of the local backend:
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://xyz.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=…
```
