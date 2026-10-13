# Deployment

The playable client is a Flutter web build published as a Cloudflare Worker
with [Workers Static Assets](https://developers.cloudflare.com/workers/static-assets/).
Supabase is the account and multiplayer backend. Edge functions have their
own workflow; this page is the Worker, branch, DNS, and project layout.

## Branch to site

| Branch | Site | Worker | How it is published |
| --- | --- | --- | --- |
| `test-launch` | https://test.restoriaidle.com | `restoria-idlerpg-staging` | Push to `test-launch`, or `npx wrangler deploy --env staging` |
| `main` | https://restoriaidle.com and https://www.restoriaidle.com | `restoria-idlerpg` | Push to `main`, or `npx wrangler deploy --env production` |

Going forward: implement on a branch from latest `test-launch` and playtest
the test site. Never commit or push to `main`. Only Conor promotes
`test-launch` to `main` by manually merging a PR, which publishes the live
site.

**Agents: never target the live Worker from a feature branch.** Bare
`npx wrangler deploy` (no `--env`) hits the sink Worker
`restoria-idlerpg-do-not-deploy`, not live. Test builds must use
`npx wrangler deploy --env staging` only. Live is only
`npx wrangler deploy --env production` (CI on `main`). Do not
`wrangler versions upload` onto `restoria-idlerpg`.

The two sites are different Workers. Deploying with `--env staging` cannot
overwrite `restoria-idlerpg` or the apex/www custom domains.

Live custom domains are bound in the Cloudflare dashboard, not listed in the
top-level Wrangler config. A deploy that declared those routes would rewrite
the live bindings.

| Extra | Target |
| --- | --- |
| Test workers.dev | https://restoria-idlerpg-staging.cburns458.workers.dev |
| Live workers.dev | https://restoria-idlerpg.cburns458.workers.dev |
| DNS zone | `restoriaidle.com` (`2965b4a468a4c56aafc36a25ce216671`) |

## Two Supabase projects

| Site | GitHub environment | Project | Ref | API URL |
| --- | --- | --- | --- | --- |
| https://test.restoriaidle.com | `staging` | Restoria test | `xlbwmxxtzrqjujvgqcuf` | https://xlbwmxxtzrqjujvgqcuf.supabase.co |
| https://restoriaidle.com | `production` | live | `fxcovagwwbptqaavispl` | https://fxcovagwwbptqaavispl.supabase.co |

Each Worker build compiles `SUPABASE_URL` and `SUPABASE_ANON_KEY` from its
GitHub environment via `scripts/cf-build.sh`. Do not put those values in
Wrangler `vars`. `SUPABASE_URL` must be exactly the API origin
(`https://fxcovagwwbptqaavispl.supabase.co` on production,
`https://xlbwmxxtzrqjujvgqcuf.supabase.co` on staging). A value of
`https://` compiles into the client as `https: //`; sign-in then POSTs to
the Worker and players see "empty response with status code 405". The
build now fails on that.

Free projects pause after about seven days of inactivity. Resume from the
dashboard or `restore_project`. That is expected for the test project if
nobody has signed in.

### Auth URLs on the test project

In the Restoria test project: Authentication → URL configuration.

- Site URL: `https://test.restoriaidle.com`
- Redirect URLs: `https://test.restoriaidle.com`, `https://test.restoriaidle.com/**`

Authentication → Providers → Email: **Confirm email** off. A new project
leaves it on. Sign-up then creates the user with no session, character
creation hits `profiles` RLS, and `updateUser` reports "Auth session
missing". Live already has Confirm email off.

Closing the tab or tapping Back on the name sheet signs that unfinished
session out. The next visit is the login gate; signing in asks for a
name again.

Live keeps `https://restoriaidle.com`.

## Tester gate (test site only)

`restoria-idlerpg-staging` runs `src/worker/staging.ts` in front of its
assets. A visitor sees a key page until they enter the value of the Worker
secret `TESTER_PASSKEY`; the Worker then sets an HttpOnly cookie derived from
it. The key is never in the repo, GitHub, or the web build. It covers both
test.restoriaidle.com and the test workers.dev address.

- Set or rotate it in the Cloudflare dashboard: Workers & Pages →
  `restoria-idlerpg-staging` → Settings → Variables and Secrets →
  **Secret** `TESTER_PASSKEY`. It must be a Secret, not a Variable: the next
  `wrangler deploy` overwrites dashboard Variables from `wrangler.toml` and
  would drop it. A GitHub secret never reaches the Worker.
- The name is exact: `TESTER_PASSKEY`, on Worker `restoria-idlerpg-staging`
  (not the live Worker). Rotating signs every tester out.
- Adding the secret attaches it to the next deploy. The version that is
  already live stays locked until that deploy finishes.
- Without the secret the test site shows a locked page; it never opens.
- `wrangler deploy` keeps existing Secrets. The staging workflow curls the
  test Worker before and after deploy and fails if that page is still locked.
- To run the gate locally, put `TESTER_PASSKEY=…` in `.dev.vars.staging`
  (git-ignored) and run `npx wrangler dev --env staging`.

The live Worker has no script, so it has no gate. The Flutter app has no
passkey of its own; `restoria-testers` is gone from the client.

## Migrations

Apply files under `supabase/migrations/` in **filename order** (the two `011_`
files are alphabetical: `011_chat_privacy` then `011_leaderboard_profile_fk`;
`20261006191030_supabase_advisor_social_hardening.sql` is last).

The agent does this through the Supabase connection (`apply_migration`):

1. Test project, when the migration lands on `test-launch`.
2. Live project, only after Conor merges `test-launch` into `main`.

Do not use `supabase db push` against either hosted project. Live's migration
history was empty when the test project was created (SQL had been pasted in
the editor), so a push would try to replay from `001`.

### Pending on live

None. The eight files that were waiting (profile guard through Wave F
cleanup) were applied to live when `efbda080` shipped to `main`.

A one-time copy of a live tester save into the test project is
`scripts/copy-save-to-test.sh`.

## Commands

From the repo root, with `CLOUDFLARE_API_TOKEN` in the environment (never in
the repo):

```bash
# Reserve test.restoriaidle.com (idempotent; does not touch apex or www)
bash scripts/cf-reserve-staging-dns.sh

# Publish the test-launch Worker (test.restoriaidle.com only)
npx wrangler deploy --env staging

# Publish the live Worker (restoriaidle.com). Requires --env production.
npx wrangler deploy --env production
```

`scripts/cf-build.sh` runs as Wrangler's build step and needs Flutter 3.47.0.
When `SUPABASE_URL` and `SUPABASE_ANON_KEY` are unset it still emits a
local-only preview bundle.

## GitHub Actions

| Workflow | Trigger | Publishes |
| --- | --- | --- |
| `deploy-worker-staging.yml` | Push to `test-launch`, or **Run workflow** | `restoria-idlerpg-staging` only |
| `deploy-worker-production.yml` | Push to `main`, or **Run workflow** | `restoria-idlerpg` only |
| `deploy.yml` | Push to `test-launch` or `main` touching `supabase/functions`, `src/game`, or the content database | Edge functions to that branch's project |

`deploy.yml` uses the same GitHub environments as the Worker workflows.
Missing `SUPABASE_ACCESS_TOKEN` or `SUPABASE_PROJECT_REF` fails the job
(`::error` + exit 1). It also refuses a crossed wire: `test-launch` will not
deploy to the live ref, and `main` will not deploy to the test ref.

The `game` function is the phase 0 server-authority prototype. The deploy
job runs `npm run bundle:game-edge` so `src/game` is inside the function
before `deno check`. See [docs/server-authority.md](server-authority.md).
Do not treat a green deploy of `game` as live `sync` / `command` — those
still return 501.

Do not redeploy the live `bazaar` function without an explicit owner OK.
Live already has migration `025_bazaar_six_slots` applied (six-slot
`bazaar_place_order` and `bazaar_orders_slot_check`); the hosted function
build is still the September three-slot client. Conor merging `test-launch`
into `main` after that OK is what updates it.

### Environment secrets

Put these on **`staging`** (test) and **`production`** (live). Values differ
per environment.

| Secret | `staging` | `production` |
| --- | --- | --- |
| `SUPABASE_URL` | https://xlbwmxxtzrqjujvgqcuf.supabase.co | https://fxcovagwwbptqaavispl.supabase.co |
| `SUPABASE_ANON_KEY` | Restoria test anon / publishable key | live anon key |
| `SUPABASE_ACCESS_TOKEN` | Supabase account access token (functions deploy) | same token is fine |
| `SUPABASE_PROJECT_REF` | `xlbwmxxtzrqjujvgqcuf` | `fxcovagwwbptqaavispl` |
| `CLOUDFLARE_API_TOKEN` | Workers Scripts Edit + Zone DNS Edit | Workers Scripts Edit |

`CLOUDFLARE_API_TOKEN` may stay a repository secret if both environments
should share it.

## Token scopes

1. Zone `restoriaidle.com`: **DNS Read**, **DNS Edit**
2. Account: **Workers Scripts Edit**
3. Zone: **Workers Routes Edit** if a custom domain is attached as a route

Do not commit the token. Do not paste it into chat. GitHub and Cursor Cloud
Agent secrets are the place for it.

<!-- token-split verify: live redeploy -->

<!-- emergency live reset after staging-token DNS update -->

<!-- emergency live reset: 2h recheck 2026-10-13T17:10Z -->
