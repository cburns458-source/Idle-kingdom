-- Friend requests and friendships, so an invite on one device lands on another.
--
-- Friends used to live only on the sender's device. That is why a request
-- showed under Sent requests and never under the other player's Friend requests.

create table if not exists public.friend_requests (
  from_user_id uuid not null references auth.users (id) on delete cascade,
  to_user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (from_user_id, to_user_id),
  check (from_user_id <> to_user_id)
);

create table if not exists public.friendships (
  user_a uuid not null references auth.users (id) on delete cascade,
  user_b uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a < user_b)
);

create index if not exists friend_requests_to_idx on public.friend_requests (to_user_id);
create index if not exists friendships_user_b_idx on public.friendships (user_b);

alter table public.friend_requests enable row level security;
alter table public.friendships enable row level security;

drop policy if exists "friend requests readable" on public.friend_requests;
create policy "friend requests readable" on public.friend_requests
  for select using (auth.uid() = from_user_id or auth.uid() = to_user_id);

drop policy if exists "friend requests insert self" on public.friend_requests;
create policy "friend requests insert self" on public.friend_requests
  for insert with check (auth.uid() = from_user_id);

drop policy if exists "friend requests delete parties" on public.friend_requests;
create policy "friend requests delete parties" on public.friend_requests
  for delete using (auth.uid() = from_user_id or auth.uid() = to_user_id);

drop policy if exists "friendships readable" on public.friendships;
create policy "friendships readable" on public.friendships
  for select using (auth.uid() = user_a or auth.uid() = user_b);

drop policy if exists "friendships insert party" on public.friendships;
create policy "friendships insert party" on public.friendships
  for insert with check (auth.uid() = user_a or auth.uid() = user_b);

drop policy if exists "friendships delete party" on public.friendships;
create policy "friendships delete party" on public.friendships
  for delete using (auth.uid() = user_a or auth.uid() = user_b);

comment on table public.friend_requests is
  'A pending friend invite. Either party may read or delete it; only the sender inserts.';
comment on table public.friendships is
  'An accepted pair. user_a is the lesser uuid so each pair is one row.';
