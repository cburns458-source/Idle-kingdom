-- Skip the Rising strength hosted-save scan once it is unlocked, and skip the
-- player_saves trigger evaluate unless this member newly reaches total level
-- 500. That removes the extra count on hall commits (the save write does not
-- change skill levels; guild_commit_hall still evaluates after the hall row).
-- Do not edit 20261016170000 or 20261016180000; those are already on test.
-- Apply on the test project only with this PR; live after Conor merges
-- test-launch into main.

create or replace function public.guild_evaluate_achievements(p_guild uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hall public.guild_halls;
  v_tiers jsonb := '[]'::jsonb;
  v_gold numeric := 0;
  v_materials numeric := 0;
  v_donors integer := 0;
  v_strong integer := 0;
  v_rising_unlocked boolean := false;
  v_now timestamptz := now();
  v_new jsonb := '[]'::jsonb;
  v_id text;
  v_ok boolean;
  v_inserted integer;
begin
  if p_guild is null then
    return '[]'::jsonb;
  end if;

  select * into v_hall
    from public.guild_halls
   where guild_id = p_guild;
  if found then
    v_tiers := coalesce(v_hall.completed_tiers, '[]'::jsonb);
    v_gold := coalesce(v_hall.gold_contributed, 0);
    v_materials := public.guild_hall_materials_spent(v_tiers);
    v_donors := public.guild_donor_count(v_hall.gold_contributed_by, v_hall.donated_by);
  end if;

  select exists (
    select 1
      from public.guild_achievements a
     where a.guild_id = p_guild
       and a.achievement_id = 'gach_rising_strength'
  ) into v_rising_unlocked;
  if not v_rising_unlocked then
    select count(*)::integer into v_strong
      from public.guild_members m
     where m.guild_id = p_guild
       and coalesce(public.bazaar_user_total_level(m.user_id), 0) >= 500;
  end if;

  for v_id, v_ok in
    select defs.id, defs.met
      from (
        select 'gach_foundations'::text as id, v_tiers ? 'build_the_hall' as met
        union all select 'gach_hall_2', v_tiers ? 'hall_bank'
        union all select 'gach_hall_3', v_tiers ? 'hall_boxing_ring'
        union all select 'gach_hall_4', v_tiers ? 'hall_indoor_garden'
        union all select 'gach_hall_arcana', v_tiers ? 'hall_arcana_station'
        union all select 'gach_hall_5', v_tiers ? 'hall_monster_cage'
        union all select 'gach_gold_100k', v_gold >= 100000
        union all select 'gach_gold_500k', v_gold >= 500000
        union all select 'gach_materials', v_materials >= 100000
        union all select 'gach_donors_10', v_donors >= 10
        union all select 'gach_donors_25', v_donors >= 25
        union all select 'gach_rising_strength', v_strong >= 25
      ) defs
  loop
    if v_ok then
      insert into public.guild_achievements (guild_id, achievement_id, unlocked_at)
      values (p_guild, v_id, v_now)
      on conflict (guild_id, achievement_id) do nothing;
      get diagnostics v_inserted = row_count;
      if v_inserted > 0 then
        v_new := v_new || jsonb_build_array(
          jsonb_build_object('id', v_id, 'unlocked_at', v_now)
        );
      end if;
    end if;
  end loop;

  return v_new;
end;
$$;

comment on function public.guild_evaluate_achievements(uuid) is
  'Idempotent guild achievement unlocks. Skips the hosted-save Rising strength scan once unlocked.';

revoke all on function public.guild_evaluate_achievements(uuid) from public, anon, authenticated;
grant execute on function public.guild_evaluate_achievements(uuid) to service_role;

create or replace function public.guild_saves_evaluate_achievements()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_guild uuid;
  v_new_level integer;
  v_old_level integer;
begin
  select guild_id into v_guild
    from public.guild_members
   where user_id = new.user_id
   limit 1;
  if v_guild is null then
    return new;
  end if;

  if exists (
    select 1
      from public.guild_achievements a
     where a.guild_id = v_guild
       and a.achievement_id = 'gach_rising_strength'
  ) then
    return new;
  end if;

  v_new_level := coalesce(public.bazaar_payload_total_level(new.payload), 0);
  v_old_level := case
    when tg_op = 'UPDATE' then coalesce(public.bazaar_payload_total_level(old.payload), 0)
    else 0
  end;
  -- Hall commits write the save then evaluate after the hall row. Skip unless
  -- this payload newly reaches 500, so a chip-in does not scan every save twice.
  if v_new_level < 500 or v_old_level >= 500 then
    return new;
  end if;

  perform public.guild_evaluate_achievements(v_guild);
  return new;
end;
$$;

comment on function public.guild_saves_evaluate_achievements() is
  'Evaluate Rising strength only when a hosted save newly reaches total level 500.';

revoke all on function public.guild_saves_evaluate_achievements() from public, anon, authenticated;
grant execute on function public.guild_saves_evaluate_achievements() to service_role;

notify pgrst, 'reload schema';
