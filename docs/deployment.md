# Deployment

The playable client is a Flutter web build published as a Cloudflare Worker
with [Workers Static Assets](https://developers.cloudflare.com/workers/static-assets/).
Supabase remains the account and multiplayer backend. Edge functions have their
own workflow; this page is the Worker and DNS layout.

## What is already live

| Role | Target | How it is published |
| --- | --- | --- |
| Production Worker | `restoria-idlerpg` | Top-level `wrangler.toml` (`npx wrangler deploy`, no `--env`) |
| Production site | `https://restoriaidle.com` and `https://www.restoriaidle.com` | Custom domains bound in the Cloudflare dashboard, not listed in Wrangler |
| Production workers.dev | `https://restoria-idlerpg.cburns458.workers.dev` | Same Worker |
| Production DNS | Zone `restoriaidle.com` (`2965b4a468a4c56aafc36a25ce216671`) | Proxied apex `AAAA 100::`, `www` CNAME to the apex |
| Edge functions | Project `fxcovagwwbptqaavispl` | `.github/workflows/deploy.yml` on push to `test-launch` |

`main` is only the initial commit. `test-launch` is the trunk players are on.

The provided Cloud Agent token can edit DNS on this zone and cannot list or
deploy Workers. A first staging publish still needs a token (or dashboard
login) with **Workers Scripts Edit** plus **Zone DNS Edit**.

## What staging adds

| Role | Target |
| --- | --- |
| Staging Worker | `restoria-idlerpg-staging` (Wrangler `--env staging`) |
| Staging site | `https://test.restoriaidle.com` |
| Staging workers.dev | `https://restoria-idlerpg-staging.cburns458.workers.dev` |

Production and staging are different Workers. Deploying staging cannot
overwrite `restoria-idlerpg` or the apex/www custom domains.

Staging currently uses the same Supabase project as production when
`SUPABASE_URL` and `SUPABASE_ANON_KEY` are set. There is only one project
today. Point staging at a different project later by giving the staging GitHub
environment its own secrets; do not put those values in Wrangler `vars`.

## Commands

From the repo root, with `CLOUDFLARE_API_TOKEN` in the environment (never in
the repo):

```bash
# Reserve test.restoriaidle.com (idempotent; does not touch apex or www)
bash scripts/cf-reserve-staging-dns.sh

# Publish the separate staging Worker and attach test.restoriaidle.com
npx wrangler deploy --env staging

# Publish the existing production Worker (does not use --env staging)
npx wrangler deploy
```

`scripts/cf-build.sh` runs as Wrangler's build step and needs Flutter 3.47.0.
When `SUPABASE_URL` and `SUPABASE_ANON_KEY` are unset it still emits a
local-only preview bundle.

## GitHub Actions

| Workflow | Trigger | Publishes |
| --- | --- | --- |
| `deploy-worker-staging.yml` | Push to `staging`, or **Run workflow** | `restoria-idlerpg-staging` only |
| `deploy-worker-production.yml` | **Run workflow** and type `deploy-production` | `restoria-idlerpg` only |
| `deploy.yml` | Push to `test-launch` (functions paths) | Supabase edge functions, not the Worker |

Repository secrets:

- `CLOUDFLARE_API_TOKEN` — Workers Scripts Edit and Zone DNS Edit. The
  DNS-only token used to reserve `test.restoriaidle.com` is not enough to
  publish a Worker.
- `SUPABASE_URL` and `SUPABASE_ANON_KEY` — compiled into the Flutter web
  bundle by `scripts/cf-build.sh`.

Optional GitHub Environments named `staging` and `production` can hold
different secret values and required reviewers.

## Token scopes

Minimum for the full staging path:

1. Zone `restoriaidle.com`: **DNS Read**, **DNS Edit**
2. Account: **Workers Scripts Edit** (so Wrangler can create
   `restoria-idlerpg-staging` and upload assets)
3. Zone: **Workers Routes Edit** if the custom-domain attach is done as a
   route rather than a dashboard custom domain

Do not commit the token. Do not paste it into chat. GitHub and Cursor Cloud
Agent secrets are the place for it.
