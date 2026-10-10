# Server-authoritative backend

The server owns every save. This page is the design for that, and the
phases that get us there. Phase 2 is live on `test-launch`: `sync` and
`command` write `player_saves`, clients adopt the server copy, and
direct client insert/update on that table is revoked. Phase 1 `shadow`
and phase 0 `prototype` stay available.

Phase 4 is done. Combat and gathering still tick on the device so the UI
stays live; the hosted save is written by `sync` and `command`. The Master
Prompt and Game Bible say the same.

## Why

`player_saves` is fully client-writable. Gold, items, and progress can be
edited in the browser. Guild contribute / hall donate / pay debt credit a
shared ledger without debiting the hosted save. Leaderboard and PvP rows
are client-written. A second device, or a crafted request, can invent
wealth or a rank.

The TypeScript rules in `src/game` already match the Dart rules through
the committed parity fixtures. `advanceSession(db, save, nowMs, random)`
and `resolveUnattendedProgress` take time and RNG as parameters, so a
server can rerun them.

## What the server will hold

Every hosted save gains three fields the client may not invent:

| Field | Role |
| --- | --- |
| `version` | Integer compare-and-swap. Replaces the `updated_at` freshness checks. A write that names the wrong version is refused. |
| `advanced_to` | Server time the simulation has reached. `sync` advances from here to now. |
| server RNG seed + counter | Loot and pool rolls come from this stream so a client cannot reroll. |

Phase 2 adds those columns on `player_saves`. The game function is the
only writer. Phase 1 still stores a parallel copy on
`player_save_shadows`.

## One `game` edge function

`verify_jwt` is on. The service-role key is read from the environment
only. Later this function is the only writer of `player_saves`.

| Action | Job |
| --- | --- |
| `prototype` | Phase 0. Times `advanceSession` and the unattended resolver on **copies** of saves. Does not write `player_saves`. |
| `shadow` | Phase 1. Replays the previous upload with the TS rules, advances the server's own copy, and logs diffs. Does not write `player_saves` and the client does not adopt the result. |
| `sync` | Phase 2. Advance from `advanced_to` to now with `advanceSession` and the unattended resolver. |
| `command` | Phase 2. Every place the Flutter session mutates a save becomes a named command, validated with the TS rules, written with a version check in one SQL call. |

Economy commands (formerly a separate wave) live under `command` too:
guild contribute, hall donate, pay debt, settle a hall tier, withdraw.
Withdrawals go through one `guild_may(actor, guild, action)` check that
reuses migration 019's rank permissions. Each is one transaction,
because the server holds both the save and the guild ledger. The Bazaar
can move into this function later.

A signed-in client calls `sync` about every two minutes and `command`
for each discrete intent. The Dart rules still tick locally; the
response replaces the local save. A snap-back is the drift detector.

## How the client behaves

The Dart rules still run every frame so the UI stays responsive. Every
`game` response replaces the local save. A Dart/TS mismatch shows up as
a visible snap-back, which is the drift detector.

Signing in is required to play. The local backend stays as a test
harness only.

## Quota and catch-up

Unattended progress costs nothing extra beyond the function call. Eight
hours offline is one `sync`. Call `sync` on player actions and roughly
every few minutes. The free plan allows about 500k function calls a
month.

Edge-function CPU is about two seconds per request. A function killed at that
limit answers HTTP 546 ("not having enough compute resources") and writes
nothing, so the next call starts from the same point with more to do. A
level-98 woodcutter away for half a day on 12-second elder yew hit exactly that.

So a hosted catch-up runs in slices. `resolveUnattendedProgress` takes a
`budgetMs` (`HOSTED_CATCH_UP_BUDGET_MS`, 600 ms of wall clock) and stops early
once it is spent, stamping `unattendedProgressAt` only as far as it simulated
and crediting play time for that span alone.

- `sync` writes the slice and answers `caughtUp: false`.
- `command` writes the slice, does not apply the intent, and answers 202 with
  `catchingUp: true`, the slice's save, and its new `version`.
- The client repeats the same call with that version, up to
  `remoteGameCatchUpAttempts` times.
- `advanced_to` only moves to now when a catch-up finishes. While slices are
  pending it stays at the start of the away window, and each slice passes it
  as `windowStartMs`, so splitting a 48-hour absence still simulates 24 hours.

## Risks

- Bundling `src/game` into Deno. The deploy job runs
  `npm run bundle:game-edge` before `deno check` and
  `supabase functions deploy`.
- Dart/TS rule drift. Parity fixtures stay the gate. Snap-back is the
  live signal.
- CPU limit on a full `unattended_cap` (24 hours) of combat ticks.

## Phases

0. **Prototype.** Bundle `src/game` into `game`. Time
   `advanceSession` and `resolveUnattendedProgress` on synthetic copies
   and, when present, a copy of the caller's hosted save. No writes. No
   client switchover.
1. **Shadow (this wave).** The server advances its own copy beside
   client uploads and logs differences on `player_save_shadow_diffs`.
   Players see no change. Loot/gold diffs are expected until phase 2
   holds a server RNG; location, activity, and play time are the signal.
2. **Commands live (this wave).** `sync` and `command` (including the
   economy commands) write. Clients switch over. Direct client
   insert/update on `player_saves` is revoked. Local-only play is
   removed.
3. **Rankings (this wave).** Server writes `leaderboard_snapshots`,
   `pvp_snapshots`, and public profile equipment. Client writes to those
   tables are revoked.
4. **Docs (done).** Master Prompt and Game Bible now say the hosted save
   is server-authoritative. Combat and gathering still tick on the device
   for the live UI.

Do not start D, E, F, or H until the owner asks.

## Phase 0 contract

`POST` the `game` function with a signed-in JWT.

```json
{ "action": "prototype", "awayMs": 28800000 }
```

`awayMs` defaults to eight hours. An optional `save` object is timed as
an extra copy; if it is omitted, a copy of the caller's `player_saves`
row is used when one exists. The function always times an idle new save
and a meadow-gathering save as well.

The response is timings and a short summary (changed flags, gathering
actions, elapsed ms). It does **not** return a save to adopt, and it
does **not** write `player_saves`.

Apply no migration for phase 0. The test project receives the function
on the next `test-launch` deploy. Live does not, until this revision is
shipped to `main`.

## Phase 1 contract

After a successful cloud save upload, the signed-in client invokes:

```json
{ "action": "shadow" }
```

The function reads `player_saves` itself. It never writes that table.

- First call for an account: store the upload as the shadow baseline and
  log an `initialized` row.
- Later calls: advance the previous upload and the server-owned copy to
  now, log `replay` (interval) and `own` (accumulated) diffs, then store
  the latest upload as the next replay baseline.
- Calls less than 90 seconds after the last real row are skipped.

The client ignores the response. Play does not snap back.

Query diffs on the test project:

```sql
select created_at, initialized, matched, own_matched, diff_count, diffs
from public.player_save_shadow_diffs
order by created_at desc
limit 20;
```

Migration `20261007040000_player_save_shadow.sql` is applied to the
**test** project with this wave. Live waits for ship.

## Phase 2 contract

`POST` the `game` function with a signed-in JWT.

```json
{ "action": "sync", "version": 3, "playSessionId": "…" }
```

```json
{ "action": "command", "command": "travel", "args": { "destinationId": "LOC-0009" }, "version": 3 }
```

`sync` advances the hosted save to now with the TS rules and a server RNG.
`command` first catches that copy up to now, then applies one named intent.
Both write with a compare-and-swap on `version`. A bazaar write bumps
`version` so the next command cannot overwrite it. A play-session mismatch
is refused.

The client adopts a `command` result. Start commands
(`start_activity`, `confirm_auto_equip`, `start_production`) keep the local
action and combat clocks when the activity matches, because the function's
`nowMs` is a round-trip later than the tap and would restart the first bar.
Periodic `sync` keeps the hosted row current and does not replace the live
tick — adopting that snapshot was rewinding the action bar and putting sold
items back. Direct insert/update/delete on `player_saves` is revoked; `SELECT`
of the caller's own row stays.

Migration `20261007050000_player_save_authority.sql` is applied to the
**test** project with this wave. Live waits for ship.

## Phase 3 contract

`submit_leaderboard` and `save_pvp_equipment` are named commands. The
function derives board rows, public `equipment_json`, and the PvP
snapshot from the hosted save. A crafted client cannot invent a rank or
a published loadout. Periodic `sync` and other commands overlay live
combat stats onto an already-published PvP row; they do not create one.

Direct client insert/update/delete on `leaderboard_snapshots` and
`pvp_snapshots` is revoked. `SELECT` stays (boards remain public; PvP
rows stay signed-in readable). A trigger refuses authenticated writes to
`profiles.equipment_json`.

```json
{ "action": "command", "command": "submit_leaderboard", "version": 3 }
```

```json
{ "action": "command", "command": "save_pvp_equipment", "version": 3 }
```

Migration `20261007060000_player_save_rankings.sql` is applied to the
**test** project with this wave. Live waits for ship.
