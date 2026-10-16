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
  Conor merges `test-launch` into `main`. A Cursor cloud agent applies the
  test migration. Say so in the summary.
- Edge functions deploy from `.github/workflows/deploy.yml`: `test-launch` to
  the test project (`staging` environment), `main` to the live project
  (`production` environment). That workflow must fail when deploy secrets are
  missing — never report success after a silent skip.
- Never commit or push to `main`. Only Conor promotes `test-launch` to `main`
  by manually merging a PR. That merge publishes the live site.

## Conor's go

- No code, migration, function deploy or PR commit until Conor gives an
  explicit go in your 1:1 chat. A group-chat agreement between bots is not a go.
- An approved plan covers only its stated scope. Any follow-up, fix or scope
  change needs a new go.

## Cursor cloud agents

Vari's rule (Conor; call him Vari):

- All code commits and pushes go through a Cursor cloud agent. Bots do not
  commit or push by hand.
- Migrations are applied by a cloud agent, to the test Supabase project.
  Never run `supabase db push`. Live migrations follow the existing process
  after Vari merges into `main`.
- Use cloud agents as much as possible: implementation, investigation and
  tests.
- Reuse the existing cloud agent for the same task or branch (follow-ups,
  fixes, review rounds) instead of launching a new one.
- Cloud agents use Grok 4.6 only.

Everything else in this file still applies: PRs into `test-launch` only,
never touch `main`, no force-push, no build or deploy file changes, Vari's
go before implementation, and only Vari merges.

## Group chat

Bots: Sys, Quest, Eco, QA, Ui, Ops, Art, Notifs, Coordinator.

- Give a task by @mentioning the bot it's for (e.g. `@Sys`).
- When you are @mentioned with a task, do it and reply only when it's done,
  or if you're blocked or need Conor's go. No "on it" or "got it" posts.
- If a message needs no follow-up, don't reply.
- Before each turn, check the room for any message addressed to you that you
  haven't acted on yet. Never skip one.
