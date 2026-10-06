# Agent workflow

Follow this file on every future prompt. It overrides older “start coding on a feature branch” habits.

Owner’s newest direct instruction still wins if it conflicts with this file.

## Loop

1. Owner sends instructions.
2. Agent inspects the repo and shares a plan. **Stop. Do not implement.**
3. Owner confirms the plan, or revises it.
4. Agent implements only the confirmed plan on `test-launch`.
5. Agent runs the checks in `AGENTS.md`, summarizes what changed, and gives a short playtest list.
6. Owner tests the live **test-launch** build and confirms it works as intended.
7. Only then does the agent ship that exact `test-launch` revision to `main`.

Do not skip the plan step. Do not skip the playtest step.

## Branches

| Branch | Role |
| --- | --- |
| `test-launch` | Only implementation branch. All approved work is committed and pushed here. |
| `main` | Ship target. Untouched until the owner confirms the test-launch playtest. |

Rules:

- Do **not** create standalone feature branches (`cursor/*` or otherwise).
- Do **not** leave finished work on a side branch for someone else to merge.
- Do **not** commit to, rebase onto, or merge into `main` until the owner says the test-launch build is good.
- A draft pull request from `test-launch` → `main` is only a ship vehicle. It must stay unmerged until step 7.

`main` currently holds only the initial commit. The playable game lives on `test-launch`. Shipping to `main` is a later, owner-approved step — not the default end of a coding turn.

## What a plan must include

Before any implementation:

- Objective in one or two sentences.
- Files / systems that will change.
- Which wave this is (see remaining work below), and what it will **not** do.
- Migration or secret work the owner has to do by hand.
- How the owner should playtest it on test-launch.
- Blocking questions, if any. If none: say so.

Then stop and wait.

## After a confirmed plan

- Implement only that wave on `test-launch`.
- Do not start the next wave until the owner playtests and approves this one, unless they explicitly asked to batch waves.
- If a change needs a new file under `supabase/migrations/`, say so plainly. Applying SQL is still the owner’s step.
- Edge functions deploy from `test-launch` via `.github/workflows/deploy.yml`. That workflow must fail when deploy secrets are missing — never report success after a silent skip.
- After the owner confirms the test-launch playtest, ship by merging or fast-forwarding that same revision to `main`. Do not re-implement on `main`.

## Remaining work (as of 2026-10-06)

Reconciled from the owner’s two lists. Advisor notices called out as intentional stay untouched: locked service-only tables, curated definer views, approved public guild helpers, and cold/unused indexes.

### Wave B — Deploy workflow (ops)

The Deploy workflow can report success while skipping edge-function deploy when `SUPABASE_ACCESS_TOKEN` or `SUPABASE_PROJECT_REF` are unset. Fail closed instead. Owner must set those GitHub repository secrets (manual deploy already happened once).

### Wave C — Server-authoritative economy transactions

Client-trusted bag/gold writes are how duplication happens today.

- Guild contributions, hall donations, and hall debt payments must debit the cloud save and credit the shared ledger in **one** server transaction.
- Cloud save writes must use an equality check on the expected `updated_at` (same idea as Bazaar RPCs), not only “refuse older stamps.”
- Hall tier settlement and withdrawals run on the server, gated by rank permissions (`guild_may` or equivalent).

### Wave D — Hosted social controls

- Wire Flutter/web blocks, mutes, and reports to the locked `player_blocks` / `player_mutes` / report tables. `send-chat` already honors blocks when rows exist.
- Move username rename + weekly cooldown + uniqueness into a server RPC. Stop listing all public usernames on the client.

### Wave E — Guild lifecycle RPCs

Policies are already hardened. Finish `guild_create` / join-open / accept-application as single server RPCs so multi-step client inserts (guild row, membership, hall, seeded goals) cannot tear.

### Wave F — Cleanup

- Remove the Citadel bazaar message-board UI, then drop or archive `bazaar_posts`.
- Delete dead `privacy_public_skills` (column, setters, local/demo paths). Skills stay public for leaderboards.

### Wave G — Server-authoritative game

The long-term fix for save/item duplication: the server runs or validates progression instead of storing a client-trusted blob. Do not start this wave until C–F are playtested. This overrides the older Master Prompt line that combat/gathering stay client-resolved for the demo.

### Wave H — Owner smoke test, then ship

In-game smoke testing is blocked on the owner’s side by a tester passkey and a second real player. The agent cannot finish that. After the owner confirms test-launch, ship that revision to `main`.

The tester passkey is a client latch in `app_flutter/lib/src/session/tester_access.dart` (`testerPasskey`). It is not a server secret. Rotate it there if the current key should change.
