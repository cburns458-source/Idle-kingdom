# Agent workflow

Follow this file on every future prompt. It overrides older “start coding on a feature branch” habits.

Owner’s newest direct instruction still wins if it conflicts with this file.

## Loop

1. Owner sends instructions.
2. Agent inspects the repo and shares a plan. **Stop. Do not implement.**
3. Owner confirms the plan, or revises it.
4. Agent implements only the confirmed plan on `test-launch`.
5. Agent runs the checks in `AGENTS.md`, summarizes what changed, and gives a short playtest list.
6. Owner tests **https://test.restoriaidle.com** (`test-launch`) and confirms it.
7. Only then does the agent ship that exact `test-launch` revision to `main`,
   which publishes **https://restoriaidle.com**.

Do not skip the plan step. Do not skip the playtest step.

## Branches

| Branch | Site | Role |
| --- | --- | --- |
| `test-launch` | https://test.restoriaidle.com | Only implementation branch. All approved work is committed and pushed here. |
| `main` | https://restoriaidle.com | Live ship target. Untouched until the owner confirms the test-launch playtest. |

Rules:

- Do **not** create standalone feature branches (`cursor/*` or otherwise).
- Do **not** leave finished work on a side branch for someone else to merge.
- Do **not** commit to, rebase onto, or merge into `main` until the owner says the test-launch build is good.
- A pull request from `test-launch` → `main` is only a ship vehicle. It must stay unmerged until step 7.

Ship by merging or fast-forwarding the confirmed `test-launch` revision to
`main`. Do not re-implement on `main`. A push to `main` publishes the live
Worker; a push to `test-launch` publishes the test Worker. See
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

- Implement only that change on `test-launch`.
- Do not start the next batch until the owner playtests and approves this one, unless they explicitly asked to batch work.
- New files under `supabase/migrations/` are applied by the agent through the
  Supabase connection: the test project first, the live project only at ship.
  Say so in the summary.
- Edge functions deploy from `.github/workflows/deploy.yml`: `test-launch` to
  the test project (`staging` environment), `main` to the live project
  (`production` environment). That workflow must fail when deploy secrets are
  missing — never report success after a silent skip.
- After the owner confirms the test-launch playtest, ship by merging or
  fast-forwarding that same revision to `main`. That push publishes the live
  site. Do not re-implement on `main`.
