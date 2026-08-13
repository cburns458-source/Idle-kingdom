-- Row-level security for the Citadel boards.
--
-- 003 created bounty_claims and bazaar_posts but left them unguarded, which is
-- what stopped the clients using them: without policies a client either cannot
-- reach a table at all or, worse, can rewrite anybody's rows.
--
-- Both boards are public reading and self-only writing, and neither can be
-- edited or deleted from a client. That is what makes the hourly bounty's first
-- completer mean something: the (hour_key, bounty_id) primary key decides the
-- race, and nobody can take a claim back once it lands.

alter table public.bounty_claims enable row level security;
alter table public.bazaar_posts enable row level security;

drop policy if exists "bounty claims readable" on public.bounty_claims;
create policy "bounty claims readable" on public.bounty_claims for select using (true);

drop policy if exists "bounty claims insert self" on public.bounty_claims;
create policy "bounty claims insert self" on public.bounty_claims
  for insert with check (auth.uid() = user_id);

drop policy if exists "bazaar posts readable" on public.bazaar_posts;
create policy "bazaar posts readable" on public.bazaar_posts for select using (true);

drop policy if exists "bazaar posts insert self" on public.bazaar_posts;
create policy "bazaar posts insert self" on public.bazaar_posts
  for insert with check (auth.uid() = user_id);

-- A notice board that never forgets becomes unreadable, and the client only ever
-- asks for the newest forty, so anything far below that is dead weight.
create or replace function public.trim_bazaar_posts() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  delete from public.bazaar_posts
  where id in (
    select id from public.bazaar_posts order by created_at desc offset 200
  );
  return null;
end $$;

drop trigger if exists trim_bazaar_posts_trigger on public.bazaar_posts;
create trigger trim_bazaar_posts_trigger
  after insert on public.bazaar_posts
  for each statement execute function public.trim_bazaar_posts();
