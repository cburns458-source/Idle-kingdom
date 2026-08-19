-- Repair leaderboard reads without depending on PostgREST embeds.
--
-- 001 created leaderboard_snapshots.user_id -> auth.users, not profiles.
-- The client then asked PostgREST to embed profiles(...), which only works when
-- a foreign key exists between those two tables. Copying 001 as written, or
-- applying it without later files, produces:
--   Could not find a relationship between 'leaderboard_snapshots' and 'profiles'
-- in the schema cache
-- on every social refresh (Guilds, Chat, and Leaderboards).
--
-- This view does the join in SQL with LEFT JOIN, so:
-- - every submitted snapshot row is listed, including players with no profile
-- - missing names read as Adventurer rather than dropping the row
-- - empty appearance_json is filled with the default look
-- PostgREST then serves a plain column named profiles, not an embed.

alter table public.leaderboard_snapshots
  add column if not exists value_secondary numeric not null default 0;

create or replace view public.leaderboard_entries
with (security_invoker = true)
as
select
  ls.user_id,
  ls.board_key,
  ls.value,
  ls.value_secondary,
  ls.updated_at,
  jsonb_build_object(
    'username', coalesce(nullif(p.username, ''), 'Adventurer'),
    'appearance_json', case
      when p.appearance_json is null or p.appearance_json = '{}'::jsonb then
        jsonb_build_object(
          'skinTone', 'APR-0001',
          'hairstyle', 'APR-0004',
          'hairColor', 'APR-0007',
          'expression', 'APR-0011',
          'beard', 'APR-0014',
          'genderPresentation', 'APR-0017'
        )
      else p.appearance_json
    end,
    'guild_id', p.guild_id,
    'guilds', case
      when g.name is null then null
      else jsonb_build_object('name', g.name)
    end
  ) as profiles
from public.leaderboard_snapshots ls
left join public.profiles p on p.user_id = ls.user_id
left join public.guilds g on g.id = p.guild_id;

comment on view public.leaderboard_entries is
  'Leaderboard rows with profile name, look, and guild folded in. Left-joined so a snapshot without a profile still appears.';

grant select on public.leaderboard_entries to anon, authenticated;

notify pgrst, 'reload schema';
