# Deployment

The playable client is a Flutter web build published as a Cloudflare Worker
with [Workers Static Assets](https://developers.cloudflare.com/workers/static-assets/).
Supabase is the account and multiplayer backend. Edge functions have their
own workflow; this page is the Worker, branch, DNS, and project layout.

## Branch to site

| Branch | Site | Worker | How it is published |
| --- | --- | --- | --- |
| `test-launch` | https://test.restoriaidle.com | `restoria-idlerpg-staging` | Push to `test-launch`, or `npx wrangler deploy --env staging` |
| `main` | https://restoriaidle.com and https://www.restoriaidle.com | `restoria-idlerpg` | Push to `main`, or `npx wrangler deploy` (no `--env`) |

Going forward: implement and playtest on `test-launch` (the test site). After
the owner confirms that build, ship the same revision to `main` so the live
site updates.

The two sites are different Workers. Deploying `test-launch` cannot overwrite
`restoria-idlerpg` or the apex/www custom domains.

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
Wrangler `vars`.

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

Live keeps `https://restoriaidle.com`.

## Migrations

Apply files under `supabase/migrations/` in **filename order** (the two `011_`
files are alphabetical: `011_chat_privacy` then `011_leaderboard_profile_fk`;
`20261006191030_supabase_advisor_social_hardening.sql` is last).

The agent does this through the Supabase connection (`apply_migration`):

1. Test project, when the migration lands on `test-launch`.
2. Live project, only at ship, when that same revision is fast-forwarded to
   `main`.

Do not use `supabase db push` against either hosted project. Live's migration
history was empty when the test project was created (SQL had been pasted in
the editor), so a push would try to replay from `001`.

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

# Publish the live Worker (restoriaidle.com). Never pass --env staging.
npx wrangler deploy
```

`scripts/cf-build.sh` runs as Wrangler's build step and needs Flutter 3.47.0.
When `SUPABASE_URL` and `SUPABASE_ANON_KEY` are unset it still emits a
local-only preview bundle.

## GitHub Actions

| Workflow | Trigger | Publishes |
| --- | --- | --- |
| `deploy-worker-staging.yml` | Push to `test-launch`, or **Run workflow** | `restoria-idlerpg-staging` only |
| `deploy-worker-production.yml` | Push to `main`, or **Run workflow** | `restoria-idlerpg` only |
| `deploy.yml` | Push to `test-launch` or `main` (functions paths) | Edge functions to that branch's project |

`deploy.yml` uses the same GitHub environments as the Worker workflows.
Missing `SUPABASE_ACCESS_TOKEN` or `SUPABASE_PROJECT_REF` fails the job
(`::error` + exit 1). It also refuses a crossed wire: `test-launch` will not
deploy to the live ref, and `main` will not deploy to the test ref.

Do not redeploy the live `bazaar` function without an explicit owner OK.
Live already has migration `025_bazaar_six_slots` applied (six-slot
`bazaar_place_order` and `bazaar_orders_slot_check`); the hosted function
build is still the September three-slot client. Shipping `main` after that
OK is what updates it.

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
