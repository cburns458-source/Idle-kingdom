# Agent workflow

Follow this file on every future prompt.

Owner’s newest direct instruction still wins if it conflicts with this file.

## Loop

1. Owner sends instructions.
2. Agent inspects the repo and shares a plan. **Stop. Do not implement.**
3. Owner confirms the plan, or revises it.
4. Agent implements only the confirmed plan on a new branch from the latest
   `origin/test-launch` and opens a pull request targeting `test-launch`.
5. Agent runs the checks in `AGENTS.md`, summarizes what changed, and gives a short playtest list.
6. Owner tests **https://test.restoriaidle.com** (`test-launch`) and confirms it.
7. Never commit or push to `main`. Only Conor promotes `test-launch` to `main`
   by manually merging a PR in GitHub, which publishes **https://restoriaidle.com**.

Do not skip the plan step. Do not skip the playtest step.

## Branches

| Branch | Site | Role |
| --- | --- | --- |
| feature branches | (via PR into `test-launch`) | Implementation. Branch from latest `origin/test-launch`. Open a PR targeting `test-launch`. |
| `test-launch` | https://test.restoriaidle.com | Test site. Agents open PRs here; they do not commit directly to `test-launch` or `main`. |
| `main` | https://restoriaidle.com | Live site. Only Conor promotes `test-launch` here by manually merging a PR. |

Rules:

- Always create a new branch from the latest `origin/test-launch`.
- Open pull requests that target `test-launch`. Never target `main`.
- Never commit or push to `main`, for any reason, even if asked to "ship".
- Never force-push to `main` or `test-launch`.
- Only Conor promotes `test-launch` to `main`, by manually merging a PR in GitHub.

A push to `test-launch` publishes the test Worker. Conor merging `test-launch`
into `main` publishes the live Worker. See
[docs/deployment.md](docs/deployment.md).

## What a plan must include

Before any implementation:

- Objective in one or two sentences.
- Files / systems that will change.
- What this change will **not** do.
- Migration or secret work the owner has to do by hand.
- How the owner should playtest it on test-launch.
- Blocking questions, if any. If none: say so.

Then stop and wait.

## After a confirmed plan

- Implement only that change on a new branch from the latest
  `origin/test-launch`, and open a pull request targeting `test-launch`.
- Do not start the next batch until the owner playtests and approves this one, unless they explicitly asked to batch work.
- New files under `supabase/migrations/` are applied by the agent through the
  Supabase connection: the test project first, the live project only after
  Conor merges `test-launch` into `main`. Say so in the summary.
- Edge functions deploy from `.github/workflows/deploy.yml`: `test-launch` to
  the test project (`staging` environment), `main` to the live project
  (`production` environment). That workflow must fail when deploy secrets are
  missing — never report success after a silent skip.
- Never commit or push to `main`. Only Conor promotes `test-launch` to `main`
  by manually merging a PR. That merge publishes the live site.
