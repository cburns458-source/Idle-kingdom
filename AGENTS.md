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
cd app_flutter && flutter analyze && flutter test && flutter build web --release
```

The formatter is the gate most easily forgotten and it fails the build on its
own, so run it last thing before committing.

## Migrations

A change that needs a new file under `supabase/migrations/` is not finished when
it is pushed: say so plainly in the summary, because applying it is the owner's
step and the game misbehaves quietly until it is done.
