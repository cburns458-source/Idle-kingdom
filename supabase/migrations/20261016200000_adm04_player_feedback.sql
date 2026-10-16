-- ADM-04: player_feedback for in-game Bug / Suggestion / Player reports.
-- Clients never write this table. The submit-feedback edge function (service
-- role) inserts and updates Discord delivery. Optional self-select so a
-- signed-in player can read their own rows; no player-visible status in P1.
-- Apply on the test project with this PR; live only after Conor merges
-- test-launch into main.

create table if not exists public.player_feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  username text not null,
  kind text not null,
  category text not null,
  title text not null,
  body text not null,
  context jsonb not null default '{}'::jsonb,
  body_hash text not null,
  status text not null default 'new',
  discord_status text not null default 'pending',
  discord_message_id text,
  discord_thread_id text,
  discord_attempts integer not null default 0,
  discord_error text,
  created_at timestamptz not null default now(),
  constraint player_feedback_kind_check
    check (kind in ('bug', 'suggestion', 'player')),
  constraint player_feedback_category_len
    check (char_length(category) between 1 and 40),
  constraint player_feedback_title_len
    check (char_length(title) between 5 and 80),
  constraint player_feedback_body_len
    check (char_length(body) between 10 and 1000),
  constraint player_feedback_context_len
    check (octet_length(context::text) <= 2048),
  constraint player_feedback_status_check
    check (status in ('new', 'triaged', 'planned', 'fixed', 'wontfix', 'duplicate')),
  constraint player_feedback_discord_status_check
    check (discord_status in ('pending', 'posted', 'failed')),
  constraint player_feedback_username_len
    check (char_length(username) between 1 and 24),
  constraint player_feedback_attempts_check
    check (discord_attempts >= 0)
);

create index if not exists player_feedback_user_created_idx
  on public.player_feedback (user_id, created_at desc);

create index if not exists player_feedback_discord_status_created_idx
  on public.player_feedback (discord_status, created_at);

create index if not exists player_feedback_user_hash_created_idx
  on public.player_feedback (user_id, body_hash, created_at desc);

create index if not exists player_feedback_created_idx
  on public.player_feedback (created_at desc);

alter table public.player_feedback enable row level security;

drop policy if exists "player_feedback_self_select" on public.player_feedback;
create policy "player_feedback_self_select"
  on public.player_feedback
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

revoke all on table public.player_feedback from public, anon, authenticated;
grant select on table public.player_feedback to authenticated;
grant all on table public.player_feedback to service_role;

notify pgrst, 'reload schema';
