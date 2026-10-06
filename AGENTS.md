# Working agreements

## Where work lands

Read `docs/AGENT_WORKFLOW.md` first. Short version:

1. Share a plan. Stop until the owner confirms it.
2. Implement only on `test-launch`. No standalone feature branches.
3. Owner playtests the live test-launch build.
4. Ship that same revision to `main` only after the owner confirms it.

`test-launch` is the test site ([test.restoriaidle.com](https://test.restoriaidle.com)).
`main` is the live site ([restoriaidle.com](https://restoriaidle.com)). Do not
commit to `main` until the owner confirms the test-launch playtest, and do not
leave work on a `cursor/*` or other side branch.

A push to `test-launch` publishes Worker `restoria-idlerpg-staging`. Shipping
that same revision to `main` publishes Worker `restoria-idlerpg`. See
[docs/deployment.md](docs/deployment.md).

**Balance / playable behavior must land on `test-launch`.** Before calling
balance work done, confirm the commit is an ancestor of `origin/test-launch`
(for example `git merge-base --is-ancestor <sha> origin/test-launch`).

## What has to pass before pushing

`test-launch` is deployed to the test site, so a broken commit on it is a
broken test game rather than a broken branch. Everything CI checks is worth
running first, because a failure found here costs a minute and one found there
costs a release:

```
dart format --output=none --set-exit-if-changed packages app_flutter/lib app_flutter/test
dart analyze
dart test packages
npm run lint
npm run typecheck
npm run gen:dart:check   # the Dart row models against src/game/data/types.ts
npm test                 # also replays the committed parity fixtures
cd supabase/functions && deno check */index.ts   # only if you touched a function
cd app_flutter && flutter analyze && flutter test && flutter build web --release --pwa-strategy=none
```

`npm run typecheck` covers `src` and `tools` and cannot cover the edge
functions, because Deno's `npm:` specifiers and `.ts` imports are not tsc's. That
is why the `deno check` line is separate, and why it needs Deno rather than node.

Run it from `supabase/functions`, not the repo root. That directory holds a
`deno.json` whose only job is to stop Deno walking up to the root `package.json`,
deciding the functions are part of a node project, and demanding they resolve
`npm:` imports out of `node_modules` — which is not how the deployed runtime
loads them.

The formatter is the gate most easily forgotten and it fails the build on its
own, so run it last thing before committing.

**CI flake note:** a red check with zero failed jobs often means the hosted
runner never acquired the job (or the forge returned a 5xx), not that the game
code failed. Retrigger the empty/failed run before debugging logic.

## Migrations

The agent applies files under `supabase/migrations/` through the Supabase
connection (`apply_migration`): the **test** project first, then the **live**
project only at ship time. Say so in the summary. The game misbehaves quietly
until the SQL is actually on that project.

Do not use `supabase db push` against the hosted projects. That command decides
what to apply from a tracking table. Live still has an empty history because
everything so far was pasted into the SQL editor, so a push would try to replay
from `001`. The early ones create policies without guards and would fail.

Edge functions are not the same: `.github/workflows/deploy.yml` deploys every
function in `supabase/functions/` on a push to `test-launch` (test project,
`staging` environment) or `main` (live project, `production` environment). The
database is left out of that on purpose. The job fails if the environment is
missing `SUPABASE_ACCESS_TOKEN` or `SUPABASE_PROJECT_REF`.
