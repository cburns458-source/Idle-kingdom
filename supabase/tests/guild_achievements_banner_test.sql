-- Guild achievement helpers and banner palette. Run against a project that
-- has 20261016170000_guild_achievements_and_banner,
-- 20261016180000_guild_achievements_qa, and
-- 20261016190000_guild_achievements_skip_rising_count.

\pset pager off

do $$
begin
  if public.guild_hall_tier_material_cost('build_the_hall') <> 1100 then
    raise exception 'build the hall materials should be 1100';
  end if;
  if public.guild_hall_materials_spent('["build_the_hall"]'::jsonb) <> 1100 then
    raise exception 'spent materials should follow completed tiers';
  end if;
  if public.guild_donor_count(
       '{"a":10,"b":0}'::jsonb,
       '{"b":true,"c":true}'::jsonb
     ) <> 3 then
    raise exception 'donor count should union gold and material donors';
  end if;
  if public.guild_banner_normalized(
       '00000000-0000-0000-0000-000000000001',
       '{"background":"slate","accent":"ivory"}'::jsonb
     ) ->> 'background' is distinct from 'slate' then
    raise exception 'default banner colours should normalise';
  end if;
  begin
    perform public.guild_banner_normalized(
      '00000000-0000-0000-0000-000000000001',
      '{"background":"gold","accent":"ivory"}'::jsonb
    );
    raise exception 'gold is not on the banner palette';
  exception
    when others then
      if sqlerrm not like 'That colour is not on the banner palette.' then
        raise;
      end if;
  end;
  if public.guild_hall_materials_spent(
       '["build_the_hall","hall_bank","hall_boxing_ring","hall_indoor_garden","hall_arcana_station","hall_monster_cage"]'::jsonb
     ) <> 202700 then
    raise exception 'all six hall tiers spend 202700 materials';
  end if;
  if position('bazaar_user_total_level' in pg_get_functiondef('public.guild_evaluate_achievements(uuid)'::regprocedure)) = 0 then
    raise exception 'rising strength must count hosted saves';
  end if;
  if position('total_level >=' in pg_get_functiondef('public.guild_evaluate_achievements(uuid)'::regprocedure)) > 0 then
    raise exception 'evaluate must not trust guild_members.total_level';
  end if;
  if position('when others' in pg_get_functiondef('public.guild_set_banner(uuid,jsonb)'::regprocedure)) > 0 then
    raise exception 'guild_set_banner must not catch-all';
  end if;
  if position('P0001' in pg_get_functiondef('public.guild_set_banner(uuid,jsonb)'::regprocedure)) = 0 then
    raise exception 'guild_set_banner must catch P0001';
  end if;
  if position('v_rising_unlocked' in pg_get_functiondef('public.guild_evaluate_achievements(uuid)'::regprocedure)) = 0 then
    raise exception 'evaluate must skip the rising strength scan once unlocked';
  end if;
  if position('bazaar_user_total_level' in pg_get_functiondef('public.guild_evaluate_achievements(uuid)'::regprocedure))
     < position('v_rising_unlocked' in pg_get_functiondef('public.guild_evaluate_achievements(uuid)'::regprocedure)) then
    raise exception 'existence check must come before the hosted-save scan';
  end if;
  if position('v_new_level < 500' in pg_get_functiondef('public.guild_saves_evaluate_achievements()'::regprocedure)) = 0 then
    raise exception 'save trigger must skip unless a member newly reaches 500';
  end if;
end $$;

\echo '--- rising strength uses hosted saves and stays unlocked after a leave ---'
do $$
declare
  v_guild uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01';
  v_leader uuid;
  v_user uuid;
  v_leaver uuid;
  v_old text;
  i integer;
begin
  insert into auth.users (id)
  select ('aaaaaaaa-0000-4000-8000-0000000000' || lpad(i::text, 2, '0'))::uuid
    from generate_series(1, 25) as s(i)
  on conflict (id) do nothing;

  v_leader := 'aaaaaaaa-0000-4000-8000-000000000001'::uuid;
  insert into public.guilds (id, name, tag, leader_id)
  values (v_guild, 'Rising QA', 'RSQ', v_leader);

  for i in 1..25 loop
    v_user := ('aaaaaaaa-0000-4000-8000-0000000000' || lpad(i::text, 2, '0'))::uuid;
    insert into public.player_saves (user_id, save_version, payload)
    values (
      v_user,
      1,
      jsonb_build_object(
        'skills', jsonb_build_array(jsonb_build_object('skillId', 'SKL-0001', 'level', 500, 'xp', 0))
      )
    )
    on conflict (user_id) do update
      set payload = excluded.payload;
    insert into public.guild_members (guild_id, user_id, role, username, total_level)
    values (
      v_guild,
      v_user,
      case when i = 1 then 'leader' else 'member' end,
      'M' || i,
      1
    );
  end loop;

  perform public.guild_evaluate_achievements(v_guild);
  if not exists (
    select 1 from public.guild_achievements
     where guild_id = v_guild and achievement_id = 'gach_rising_strength'
  ) then
    raise exception 'save-based 500 should unlock rising strength even when roster total_level is 1';
  end if;

  -- Separate case: the 25th member joining at 500+ unlocks through the
  -- guild_members insert trigger alone. Saves are written before the join so
  -- the player_saves trigger is a no-op. Do not call guild_evaluate_achievements.
  insert into auth.users (id)
  select ('cccccccc-0000-4000-8000-0000000000' || lpad(i::text, 2, '0'))::uuid
    from generate_series(1, 25) as s(i)
  on conflict (id) do nothing;
  insert into public.guilds (id, name, tag, leader_id)
  values (
    'cccccccc-cccc-cccc-cccc-cccccccccc01',
    'Join QA',
    'J25',
    'cccccccc-0000-4000-8000-000000000001'::uuid
  );
  for i in 1..24 loop
    v_user := ('cccccccc-0000-4000-8000-0000000000' || lpad(i::text, 2, '0'))::uuid;
    insert into public.player_saves (user_id, save_version, payload)
    values (
      v_user,
      1,
      jsonb_build_object(
        'skills', jsonb_build_array(jsonb_build_object('skillId', 'SKL-0001', 'level', 500, 'xp', 0))
      )
    )
    on conflict (user_id) do update
      set payload = excluded.payload;
    insert into public.guild_members (guild_id, user_id, role, username, total_level)
    values (
      'cccccccc-cccc-cccc-cccc-cccccccccc01',
      v_user,
      case when i = 1 then 'leader' else 'member' end,
      'J' || i,
      1
    );
  end loop;
  if exists (
    select 1 from public.guild_achievements
     where guild_id = 'cccccccc-cccc-cccc-cccc-cccccccccc01'
       and achievement_id = 'gach_rising_strength'
  ) then
    raise exception '24 members at 500 must not unlock rising strength';
  end if;
  v_user := 'cccccccc-0000-4000-8000-000000000025'::uuid;
  insert into public.player_saves (user_id, save_version, payload)
  values (
    v_user,
    1,
    jsonb_build_object(
      'skills', jsonb_build_array(jsonb_build_object('skillId', 'SKL-0001', 'level', 500, 'xp', 0))
    )
  )
  on conflict (user_id) do update
    set payload = excluded.payload;
  insert into public.guild_members (guild_id, user_id, role, username, total_level)
  values (
    'cccccccc-cccc-cccc-cccc-cccccccccc01',
    v_user,
    'member',
    'J25',
    1
  );
  if not exists (
    select 1 from public.guild_achievements
     where guild_id = 'cccccccc-cccc-cccc-cccc-cccccccccc01'
       and achievement_id = 'gach_rising_strength'
  ) then
    raise exception '25th member joining at 500 must unlock rising strength through the join trigger';
  end if;
  delete from public.guild_achievements where guild_id = 'cccccccc-cccc-cccc-cccc-cccccccccc01';
  delete from public.guild_members where guild_id = 'cccccccc-cccc-cccc-cccc-cccccccccc01';
  delete from public.guilds where id = 'cccccccc-cccc-cccc-cccc-cccccccccc01';
  delete from public.player_saves
   where user_id in (
     select ('cccccccc-0000-4000-8000-0000000000' || lpad(i::text, 2, '0'))::uuid
       from generate_series(1, 25) as s(i)
   );
  delete from auth.users
   where id in (
     select ('cccccccc-0000-4000-8000-0000000000' || lpad(i::text, 2, '0'))::uuid
       from generate_series(1, 25) as s(i)
   );

  v_old := pg_get_functiondef('public.bazaar_user_total_level(uuid)'::regprocedure);
  begin
    create or replace function public.bazaar_user_total_level(p_user_id uuid)
    returns integer
    language plpgsql
    as $f$
    begin
      raise exception 'rising strength count should be skipped';
    end;
    $f$;
    perform public.guild_evaluate_achievements(v_guild);
    update public.player_saves
       set payload = payload
     where user_id = v_leader;
    execute v_old;
  exception
    when others then
      execute v_old;
      raise;
  end;

  v_leaver := 'aaaaaaaa-0000-4000-8000-000000000025'::uuid;
  delete from public.guild_members where guild_id = v_guild and user_id = v_leaver;
  perform public.guild_evaluate_achievements(v_guild);
  if not exists (
    select 1 from public.guild_achievements
     where guild_id = v_guild and achievement_id = 'gach_rising_strength'
  ) then
    raise exception 'leaving after unlock must keep rising strength';
  end if;

  delete from public.guild_achievements where guild_id = v_guild;
  delete from public.guild_members where guild_id = v_guild;
  delete from public.guilds where id = v_guild;
  delete from public.player_saves
   where user_id in (
     select ('aaaaaaaa-0000-4000-8000-0000000000' || lpad(i::text, 2, '0'))::uuid
       from generate_series(1, 25) as s(i)
   );
  delete from auth.users
   where id in (
     select ('aaaaaaaa-0000-4000-8000-0000000000' || lpad(i::text, 2, '0'))::uuid
       from generate_series(1, 25) as s(i)
   );

  insert into auth.users (id)
  select ('bbbbbbbb-0000-4000-8000-0000000000' || lpad(i::text, 2, '0'))::uuid
    from generate_series(1, 25) as s(i)
  on conflict (id) do nothing;
  insert into public.guilds (id, name, tag, leader_id)
  values (
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01',
    'Forged QA',
    'FRQ',
    'bbbbbbbb-0000-4000-8000-000000000001'::uuid
  );
  for i in 1..25 loop
    v_user := ('bbbbbbbb-0000-4000-8000-0000000000' || lpad(i::text, 2, '0'))::uuid;
    insert into public.guild_members (guild_id, user_id, role, username, total_level)
    values (
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01',
      v_user,
      case when i = 1 then 'leader' else 'member' end,
      'F' || i,
      1
    );
  end loop;
  if coalesce(
       public.bazaar_user_total_level('bbbbbbbb-0000-4000-8000-000000000002'::uuid),
       0
     ) <> 0 then
    raise exception 'a member with no save must count as total level 0';
  end if;
  update public.guild_members
     set total_level = 500
   where guild_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01';
  perform public.guild_evaluate_achievements('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01');
  if exists (
    select 1 from public.guild_achievements
     where guild_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01'
       and achievement_id = 'gach_rising_strength'
  ) then
    raise exception 'writing guild_members.total_level = 500 must not unlock rising strength';
  end if;
  delete from public.guild_achievements where guild_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01';
  delete from public.guild_members where guild_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01';
  delete from public.guilds where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01';
  delete from public.player_saves
   where user_id in (
     select ('bbbbbbbb-0000-4000-8000-0000000000' || lpad(i::text, 2, '0'))::uuid
       from generate_series(1, 25) as s(i)
   );
  delete from auth.users
   where id in (
     select ('bbbbbbbb-0000-4000-8000-0000000000' || lpad(i::text, 2, '0'))::uuid
       from generate_series(1, 25) as s(i)
   );
end $$;
