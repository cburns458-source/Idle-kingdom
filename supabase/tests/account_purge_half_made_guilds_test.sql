-- Four keep/purge cases for public.account_purge_half_made_guilds().
-- Run against a project that has 20261017155300_account_purge_half_made_guilds.
-- Cleans up its own fixture guilds even when a case fails.

\pset pager off

do $$
declare
  v_founder uuid;
  v_member uuid;
  v_half uuid := 'aaaaaaaa-bbbb-4ccc-8ddd-000000000001';
  v_empty uuid := 'aaaaaaaa-bbbb-4ccc-8ddd-000000000002';
  v_members uuid := 'aaaaaaaa-bbbb-4ccc-8ddd-000000000003';
  v_history uuid := 'aaaaaaaa-bbbb-4ccc-8ddd-000000000004';
  v_fresh uuid := 'aaaaaaaa-bbbb-4ccc-8ddd-000000000005';
  v_purged integer;
begin
  delete from public.guild_members
   where guild_id in (v_half, v_empty, v_members, v_history, v_fresh);
  delete from public.guilds
   where id in (v_half, v_empty, v_members, v_history, v_fresh)
      or name like 'ZZ Half-made purge %'
      or tag like 'ZZHM_';

  select u.id into v_founder
    from auth.users u
   order by u.created_at
   limit 1;
  if v_founder is null then
    raise exception 'need an auth user to own fixture guilds.leader_id';
  end if;

  select u.id into v_member
    from auth.users u
   where not exists (select 1 from public.guild_members m where m.user_id = u.id)
   order by u.created_at
   limit 1;
  if v_member is null then
    raise exception 'need a user who is not already in a guild';
  end if;

  -- 1. Half-made: no members, no leader history, no hall, no achievements, >1h.
  insert into public.guilds (id, name, tag, leader_id, created_at)
  values (v_half, 'ZZ Half-made purge 1', 'ZZHM1', v_founder, timezone('utc', now()) - interval '2 hours');

  -- 2. Real empty guild: no members, but a hall and an achievement.
  insert into public.guilds (id, name, tag, leader_id, created_at)
  values (v_empty, 'ZZ Half-made purge 2', 'ZZHM2', v_founder, timezone('utc', now()) - interval '2 hours');
  insert into public.guild_halls (guild_id) values (v_empty);
  insert into public.guild_achievements (guild_id, achievement_id)
  values (v_empty, 'gach_foundations');

  -- 3a. Real guild, no hall, current member (recruit — not a leader row).
  insert into public.guilds (id, name, tag, leader_id, created_at)
  values (v_members, 'ZZ Half-made purge 3', 'ZZHM3', v_founder, timezone('utc', now()) - interval '2 hours');
  insert into public.guild_members (guild_id, user_id, role, username)
  values (v_members, v_member, 'recruit', 'Purge fixture');

  -- 3b. Real guild, no hall, no members now, but a leftover leader-row log.
  insert into public.guilds (id, name, tag, leader_id, created_at)
  values (v_history, 'ZZ Half-made purge 4', 'ZZHM4', v_founder, timezone('utc', now()) - interval '2 hours');
  insert into public.guild_log_entries (guild_id, kind, role, message)
  values (v_history, 'leave', 'leader', 'Former leader left.');

  -- 4. Otherwise half-made, but younger than 1 hour.
  insert into public.guilds (id, name, tag, leader_id, created_at)
  values (v_fresh, 'ZZ Half-made purge 5', 'ZZHM5', v_founder, timezone('utc', now()) - interval '15 minutes');

  v_purged := public.account_purge_half_made_guilds();
  if v_purged < 1 then
    raise exception 'a half-made guild gets purged';
  end if;
  if exists (select 1 from public.guilds where id = v_half) then
    raise exception 'a half-made guild gets purged';
  end if;
  if not exists (select 1 from public.guilds where id = v_empty) then
    raise exception 'a real guild with no members is kept';
  end if;
  if not exists (select 1 from public.guilds where id = v_members)
     or not exists (select 1 from public.guilds where id = v_history) then
    raise exception 'a real guild with no hall but with members or a leader history is kept';
  end if;
  if not exists (select 1 from public.guilds where id = v_fresh) then
    raise exception 'a guild under an hour old is kept';
  end if;

  delete from public.guild_members
   where guild_id in (v_half, v_empty, v_members, v_history, v_fresh);
  delete from public.guilds
   where id in (v_empty, v_members, v_history, v_fresh);
exception
  when others then
    delete from public.guild_members
     where guild_id in (v_half, v_empty, v_members, v_history, v_fresh);
    delete from public.guilds
     where id in (v_half, v_empty, v_members, v_history, v_fresh)
        or name like 'ZZ Half-made purge %'
        or tag like 'ZZHM_';
    raise;
end $$;

\echo 'account_purge_half_made_guilds: four keep/purge cases passed'
