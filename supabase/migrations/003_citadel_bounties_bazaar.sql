-- Citadel hourly bounties (first completer) + Grand Bazaar board posts.
-- Local demo mode uses the in-browser backend; apply this in Supabase for remote multiplayer.

create table if not exists public.bounty_claims (
  hour_key text not null,
  bounty_id text not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  username text not null,
  claimed_at timestamptz not null default now(),
  primary key (hour_key, bounty_id)
);

create index if not exists bounty_claims_user_idx
  on public.bounty_claims (user_id, claimed_at desc);

create table if not exists public.bazaar_posts (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('message', 'recruit', 'trade')),
  user_id uuid not null references auth.users (id) on delete cascade,
  username text not null,
  body text not null,
  created_at timestamptz not null default now()
);

create index if not exists bazaar_posts_created_idx
  on public.bazaar_posts (created_at desc);
