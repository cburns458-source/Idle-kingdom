-- Fold the guild tag into leaderboard_entries so player rows can show [TAG]Name.
--
-- 012 joined guilds as `{ name }`. Nearby and chat already know the tag; the
-- board should not have to look it up separately or fall back to "No guild".

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
      else jsonb_build_object('name', g.name, 'tag', g.tag)
    end
  ) as profiles
from public.leaderboard_snapshots ls
left join public.profiles p on p.user_id = ls.user_id
left join public.guilds g on g.id = p.guild_id;

comment on view public.leaderboard_entries is
  'Leaderboard rows with profile name, look, guild name, and guild tag folded in. Left-joined so a snapshot without a profile still appears.';

grant select on public.leaderboard_entries to anon, authenticated;

notify pgrst, 'reload schema';
