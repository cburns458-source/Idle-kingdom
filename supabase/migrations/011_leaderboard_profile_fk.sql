-- Leaderboard reads ask PostgREST to embed profiles(...), which only works when
-- a foreign key exists between leaderboard_snapshots and profiles. The original
-- table referenced auth.users, so the schema cache had no such relationship and
-- every social refresh surfaced:
--   Could not find a relationship between 'leaderboard_snapshots' and 'profiles'
-- in the schema cache.

delete from public.leaderboard_snapshots ls
where not exists (
  select 1 from public.profiles p where p.user_id = ls.user_id
);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'leaderboard_snapshots_user_id_profiles_fkey'
  ) then
    alter table public.leaderboard_snapshots
      add constraint leaderboard_snapshots_user_id_profiles_fkey
      foreign key (user_id) references public.profiles (user_id) on delete cascade;
  end if;
end $$;

notify pgrst, 'reload schema';
