# Working agreements

## Where work lands

`test-launch` is the branch the test launch is played from, and it is the trunk:
`main` holds only the initial commit. Push finished work straight to
`test-launch` rather than leaving it on a branch for someone to merge.

Standing since 18 Aug 2026, until the owner says otherwise.

A feature branch is still worth keeping while the work is in progress, and worth
pushing so there is a record of it, but it is not where the work stops.

## What has to pass before pushing

`test-launch` is deployed, so a broken commit on it is a broken game rather than
a broken branch. Everything CI checks is worth running first, because a failure
found here costs a minute and one found there costs a release:

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

## Migrations

A change that needs a new file under `supabase/migrations/` is not finished when
it is pushed: say so plainly in the summary, because applying it is the owner's
step and the game misbehaves quietly until it is done.

Edge functions are not the same: `.github/workflows/deploy.yml` deploys every
function in `supabase/functions/` on a push to `test-launch`. The database is left
out of that on purpose. `supabase db push` works out what to apply from a tracking
table that migrations pasted into the SQL editor never wrote to, so on this
project it would try to replay from `001`, and the early ones create policies
without guards and would fail.
