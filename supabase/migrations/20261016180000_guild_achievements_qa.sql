-- QA follow-up for guild achievements (SOC-01). Do not edit
-- 20261016170000; that file is already on the test project.
-- Apply on the test project only with this PR; live after Conor merges
-- test-launch into main.
--
-- Rising strength counts hosted saves through bazaar_user_total_level, not
-- the client-writable guild_members.total_level column.
-- Guild reset restores guilds.banner to the palette default.
-- guild_set_banner catches only P0001 so unexpected errors are not returned
-- as sqlerrm.
--
-- debt_paid_by duplication: guild_commit_hall (20261016170000) still assigns
--   debt_paid_by = coalesce(v_applied -> 'gold_contributed_by', gold_contributed_by)
-- next to gold_contributed_by. debt_paid_by is a legacy alias of
-- gold_contributed_by, kept in lockstep for older hall readers. It is not a
-- second gold pool. This file does not change that write.

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

  select count(*)::integer into v_strong
    from public.guild_members m
   where m.guild_id = p_guild
     and coalesce(public.bazaar_user_total_level(m.user_id), 0) >= 500;

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
  'Idempotent guild achievement unlocks from hall state and hosted save levels.';

revoke all on function public.guild_evaluate_achievements(uuid) from public, anon, authenticated;
grant execute on function public.guild_evaluate_achievements(uuid) to service_role;

drop trigger if exists guild_members_evaluate_achievements on public.guild_members;
create trigger guild_members_evaluate_achievements
  after insert or delete or update of guild_id on public.guild_members
  for each row
  execute function public.guild_members_evaluate_achievements();

create or replace function public.guild_saves_evaluate_achievements()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_guild uuid;
begin
  select guild_id into v_guild
    from public.guild_members
   where user_id = new.user_id
   limit 1;
  if v_guild is not null then
    perform public.guild_evaluate_achievements(v_guild);
  end if;
  return new;
end;
$$;

comment on function public.guild_saves_evaluate_achievements() is
  'Re-evaluate guild achievements when a hosted save payload changes.';

revoke all on function public.guild_saves_evaluate_achievements() from public, anon, authenticated;
grant execute on function public.guild_saves_evaluate_achievements() to service_role;

drop trigger if exists guild_saves_evaluate_achievements on public.player_saves;
create trigger guild_saves_evaluate_achievements
  after insert or update of payload on public.player_saves
  for each row
  execute function public.guild_saves_evaluate_achievements();

create or replace function public.guild_set_banner(p_guild uuid, p_banner jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_clean jsonb;
begin
  if v_me is null then
    return jsonb_build_object('ok', false, 'reason', 'Sign in first.');
  end if;
  if p_guild is null then
    return jsonb_build_object('ok', false, 'reason', 'Missing guild.');
  end if;
  if not coalesce(public.is_guild_manager(p_guild), false) then
    return jsonb_build_object(
      'ok', false,
      'reason', 'Only the guild leader or an officer can change the banner.'
    );
  end if;
  begin
    v_clean := public.guild_banner_normalized(p_guild, coalesce(p_banner, '{}'::jsonb));
  exception
    when sqlstate 'P0001' then
      return jsonb_build_object('ok', false, 'reason', sqlerrm);
  end;
  update public.guilds
     set banner = v_clean
   where id = p_guild;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'That guild could not be found.');
  end if;
  return jsonb_build_object('ok', true, 'banner', v_clean);
end;
$$;

revoke all on function public.guild_set_banner(uuid, jsonb) from public, anon;
grant execute on function public.guild_set_banner(uuid, jsonb) to authenticated, service_role;

comment on column public.guild_halls.debt_paid_by is
  'Legacy alias of gold_contributed_by. guild_commit_hall writes both in lockstep for older hall readers. Not a second gold pool.';

update public.guilds
   set banner = '{"background":"slate","accent":"ivory","emblem":null,"border":null}'::jsonb;

notify pgrst, 'reload schema';
