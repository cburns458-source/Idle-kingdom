# Deployment

The playable client is a Flutter web build published as a Cloudflare Worker
with [Workers Static Assets](https://developers.cloudflare.com/workers/static-assets/).
Supabase remains the account and multiplayer backend. Edge functions have their
own workflow; this page is the Worker, branch, and DNS layout.

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
| Edge functions | Project `fxcovagwwbptqaavispl`, `.github/workflows/deploy.yml` on push to `test-launch` |

There is one Supabase project today. Both Worker builds use it when
`SUPABASE_URL` and `SUPABASE_ANON_KEY` are set. Point the test Worker at a
different project later by giving the `staging` GitHub environment its own
secrets; do not put those values in Wrangler `vars`.

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
| `deploy.yml` | Push to `test-launch` (functions paths) | Supabase edge functions, not the Worker |

Repository secrets:

- `CLOUDFLARE_API_TOKEN` — Workers Scripts Edit and Zone DNS Edit. A DNS-only
  token is not enough to publish a Worker.
- `SUPABASE_URL` and `SUPABASE_ANON_KEY` — compiled into the Flutter web
  bundle by `scripts/cf-build.sh`.

Optional GitHub Environments named `staging` and `production` can hold
different secret values and required reviewers.

## Token scopes

1. Zone `restoriaidle.com`: **DNS Read**, **DNS Edit**
2. Account: **Workers Scripts Edit**
3. Zone: **Workers Routes Edit** if a custom domain is attached as a route

Do not commit the token. Do not paste it into chat. GitHub and Cursor Cloud
Agent secrets are the place for it.
