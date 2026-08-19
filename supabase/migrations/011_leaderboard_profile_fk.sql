-- Optional FK so a direct embed of profiles on leaderboard_snapshots can work.
-- Existing snapshot rows without a profile are left in place (NOT VALID).
-- The client reads public.leaderboard_entries (012), which left-joins profiles
-- and therefore still lists those rows.

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'leaderboard_snapshots_user_id_profiles_fkey'
  ) then
    alter table public.leaderboard_snapshots
      add constraint leaderboard_snapshots_user_id_profiles_fkey
      foreign key (user_id) references public.profiles (user_id) on delete cascade
      not valid;
  end if;
end $$;

notify pgrst, 'reload schema';
