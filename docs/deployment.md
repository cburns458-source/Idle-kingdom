# Deployment

The playable client is a Flutter web build published as a Cloudflare Worker
with [Workers Static Assets](https://developers.cloudflare.com/workers/static-assets/).
Supabase is the account and multiplayer backend. Edge functions have their
own workflow; this page is the Worker, branch, DNS, and project layout.

## Branch to site

| Branch | Site | Worker | How it is published |
| --- | --- | --- | --- |
| `test-launch` | https://test.restoriaidle.com | `restoria-idlerpg-staging` | GitHub Actions (`deploy-worker-staging.yml`) on push to `test-launch` |
| `main` | https://restoriaidle.com and https://www.restoriaidle.com | `restoria-idlerpg` | GitHub Actions (`deploy-worker-production.yml`) on push to `main` |

GitHub Actions is the only Worker deployer. Cloudflare Workers Builds is
disconnected from both Workers. Wrangler is pinned at `4.150.0` in
`package.json`; the workflows run `npm ci` and that local CLI (`npm run
deploy:staging` / `deploy:production`). Do not merge Cloudflare autofix PRs
that rename the top-level `wrangler.toml` `name` —
`restoria-idlerpg-do-not-deploy` is an intentional sink.

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

`.github/workflows/deploy.yml` deploys edge functions only; it never applies
migrations. Each file below is run by hand on each project (test
`xlbwmxxtzrqjujvgqcuf`, live `fxcovagwwbptqaavispl`) and recorded in
`supabase_migrations.schema_migrations` under the file's exact version (for
example `20261012170000`), never a new timestamp.

On live:

1. Run them only after Conor approves, the change is merged to `main`, and the
   live deploy carrying the server code (the `bazaar` function refusing
   untradeable items) has finished.
2. Before each cleanup, Economy saves a list of the open orders it will cancel,
   so QA can check each refund in `bazaar_collect` (reason `'cancelled'`).
3. Run them in the order listed.
4. Afterwards, confirm each version appears in `schema_migrations` and zero open
   orders remain for the affected items.

Checklist, in order:

1. [ ] `20261012170000_bazaar_cancel_untradeable_orders.sql` (BUG-02). Cancels
   open Bazaar orders for the four untradeable items (ITEM-0406, ITEM-0313,
   ITEM-0299, ITEM-0300) through `bazaar_cancel_order`. On each project, apply
   it only after the `bazaar` function that refuses those items has deployed
   there (test: after the PR lands on `test-launch`; live: after Conor merges
   to `main`). Safe to re-run.
   Status: applied on test Oct 12 2026 (0 orders cancelled); live pending.
2. [ ] `20261012200000_bazaar_cancel_warhammer_orders.sql` (BUG-02). Cancels
   open Bazaar orders for the Dwarven Warhammer (ITEM-0123) through
   `bazaar_cancel_order`. Apply after #314 deploys: Economy runs it on test
   once the PR lands on `test-launch`; live only after Conor approves and
   merges to `main`. Safe to re-run.
   Status: applied on test Oct 12 2026 (0 orders cancelled); live pending.
3. [ ] `20261007045115_revoke_hall_economy_rpcs.sql`. Revokes client execute on
   `guild_pay_hall_debt(numeric)` and `guild_donate_hall_item(text, numeric)`;
   the `game` function handles both now. The same two revokes are at the end of
   `20261007050000_player_save_authority.sql`, which live already has, so this
   should change nothing there; it records the version test has. Safe to
   re-run.
   Status: applied on test (version `20261007045115`); live pending.
4. [ ] `20261016120000_guild_hall_tiers.sql` (SOC-01). Running gold total,
   `guild_may`, hall revision CAS, guild bank jsonb, guild log, and
   `guild_commit_hall`. Apply to test when this PR lands on `test-launch`; live
   only after Conor merges `test-launch` into `main`. Do not apply to live
   before the game function that writes through `guild_commit_hall` is on
   `restoria-idlerpg`.
   Status: applied on test Oct 16 2026 (MCP version `20261016061935`, file
   `20261016120000`); live pending.
5. [ ] `20261016140000_guild_commit_hall_save_delta.sql` (SOC-01). Hall gold and
   storehouse from hosted save deltas (8-argument `guild_commit_hall`). Apply
   to test with this PR; live only after Conor merges `test-launch` into
   `main`. Must land before or together with `20261016150000` and the `game`
   function that passes `p_before`.
   Status: applied on test Oct 16 2026 (file `20261016140000`); live pending.
6. [ ] `20261016150000_guild_commit_hall_caught_up_save.sql` (SOC-01). Drops the
   8-argument `guild_commit_hall` and replaces it with the 9-argument function
   that takes `p_before` (the caught-up save). Refuses gold past the 1M cap and
   a mismatched bank. Apply to test with this PR; live only after Conor merges
   `test-launch` into `main`. Do not apply to live before the `game` function
   that passes `p_before` is on `restoria-idlerpg`. This file and
   `20261016140000` must land before or together with that function.
   Status: applied on test Oct 16 2026 (file `20261016150000`); live pending.
7. [ ] `20261016170000_guild_achievements_and_banner.sql` (SOC-01). Guild
   achievement unlocks, hall `donated_by`, and `guilds.banner`. Apply to test
   with this PR; live only after Conor merges `test-launch` into `main`.
   Status: applied on test Oct 16 2026 (file `20261016170000`, MCP
   `guild_achievements_and_banner` plus engine follow-ups); live pending.
8. [ ] `20261016180000_guild_achievements_qa.sql` (SOC-01). Rising strength
   counts hosted saves via `bazaar_user_total_level`, guild reset restores
   `guilds.banner` to the default, `guild_set_banner` catches only P0001.
   Apply to test with this PR; live only after Conor merges `test-launch`
   into `main`. Do not edit `20261016170000`.
   Status: applied on test Oct 16 2026 (file `20261016180000`, MCP
   `20261016120815` / `guild_achievements_qa`); live pending.
9. [ ] `20261016190000_guild_achievements_skip_rising_count.sql` (SOC-01).
   Skip the Rising strength hosted-save scan once unlocked; save-payload
   trigger only evaluates when a member newly reaches total level 500.
   Apply to test with this PR; live only after Conor merges `test-launch`
   into `main`. Do not edit `20261016170000` or `20261016180000`.
   Status: applied on test Oct 16 2026 (file `20261016190000`, MCP
   `20261016122648` / `guild_achievements_skip_rising_count`); live pending.

10. [ ] `20261016200000_adm04_player_feedback.sql` (ADM-04). `player_feedback`
    table, RLS on, no client writes, optional self-select, revoke from anon.
    Apply to test with this PR; live only after Conor merges `test-launch`
    into `main`. Do not apply to live before the `submit-feedback` function
    is on `restoria-idlerpg`.
    Status: applied on test Oct 16 2026 (MCP `adm04_player_feedback` plus
    `adm04_player_feedback_revoke_writes`); live pending.

Skip `20261016160000_guild_hall_paid_off_gold.sql`. Guilds reset with this
update, so paid-off halls are not migrated. Already applied on test Oct 16
2026 (file `20261016160000`, MCP `20261016111026`); leave those rows as-is.
Do not apply on live.

The eight files before that (profile guard through Wave F cleanup) were applied
to live when `efbda080` shipped to `main`.

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

Actions is the only Worker deployer. Workers Builds is disconnected from both
`restoria-idlerpg-staging` and `restoria-idlerpg`. Both Worker workflows
install the repo-pinned wrangler (`4.150.0`) with `npm ci` rather than
`npx wrangler@latest`.

| Workflow | Trigger | Publishes |
| --- | --- | --- |
| `deploy-worker-staging.yml` | Push to `test-launch`, or **Run workflow** | `restoria-idlerpg-staging` only |
| `deploy-worker-production.yml` | Push to `main`, or **Run workflow** | `restoria-idlerpg` only |
| `deploy.yml` | Push to `test-launch` or `main` touching `supabase/functions`, `src/game`, or the content database | Edge functions to that branch's project (not a Worker) |

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

### Supabase function secrets (test project)

Set these on the Restoria **test** project only (Edge Functions → Secrets).
Never put the values in the client, the repo, or GitHub. Conor sets them.

| Secret | Purpose |
| --- | --- |
| `FEEDBACK_DISCORD_WEBHOOK_URL` | Staff-only Discord forum webhook for ADM-04 submit-feedback |
| `FEEDBACK_DISCORD_TAG_IDS` | JSON map of forum tag ids, e.g. `{"bug":"…","idea":"…","report":"…"}`. Optional; missing keys are skipped. |

Live gets its own webhook later, after Conor merges `test-launch` into `main`.

## Token scopes

1. Zone `restoriaidle.com`: **DNS Read**, **DNS Edit**
2. Account: **Workers Scripts Edit**
3. Zone: **Workers Routes Edit** if a custom domain is attached as a route

Do not commit the token. Do not paste it into chat. GitHub and Cursor Cloud
Agent secrets are the place for it.

<!-- token-split verify: staging redeploy -->

<!-- token-split verify: staging dns token -->

<!-- token-split verify: staging workers routes edit -->
