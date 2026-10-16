-- Guild-wide achievements (cosmetic, unlock once) and a small banner JSON
-- on public.guilds. Evaluate from hall commits and membership level changes.
-- Apply on the test project only with this PR; live after Conor merges
-- test-launch into main.

alter table public.guilds
  add column if not exists banner jsonb not null default
    '{"background":"slate","accent":"ivory","emblem":null,"border":null}'::jsonb;

comment on column public.guilds.banner is
  'Cosmetic hall banner: palette colour ids plus an unlocked emblem and border.';

alter table public.guild_halls
  add column if not exists donated_by jsonb not null default '{}'::jsonb;

comment on column public.guild_halls.donated_by is
  'Members who donated hall materials, keyed by user id. Gold donors are also in gold_contributed_by.';

create table if not exists public.guild_achievements (
  guild_id uuid not null references public.guilds (id) on delete cascade,
  achievement_id text not null,
  unlocked_at timestamptz not null default now(),
  primary key (guild_id, achievement_id)
);

comment on table public.guild_achievements is
  'Guild-wide cosmetic unlocks. Inserts are idempotent; unlocked_at is kept.';

alter table public.guild_achievements enable row level security;

drop policy if exists "guild achievements readable by members" on public.guild_achievements;
create policy "guild achievements readable by members"
  on public.guild_achievements
  for select
  to authenticated
  using (public.guild_role_of(guild_id, (select auth.uid())) is not null);

revoke all on table public.guild_achievements from anon, authenticated;
grant select on table public.guild_achievements to authenticated;
grant all on table public.guild_achievements to service_role;

create or replace function public.guild_hall_tier_material_cost(p_tier_id text)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select case p_tier_id
    when 'build_the_hall' then 1100
    when 'hall_bank' then 40320
    when 'hall_boxing_ring' then 40320
    when 'hall_indoor_garden' then 40320
    when 'hall_arcana_station' then 40320
    when 'hall_monster_cage' then 40320
    else 0
  end;
$$;

create or replace function public.guild_hall_materials_spent(p_completed jsonb)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select coalesce((
    select sum(public.guild_hall_tier_material_cost(elem))
      from jsonb_array_elements_text(coalesce(p_completed, '[]'::jsonb)) as elem
  ), 0);
$$;

create or replace function public.guild_donor_count(p_gold_by jsonb, p_donated_by jsonb)
returns integer
language sql
immutable
set search_path = ''
as $$
  select count(*)::integer from (
    select key
      from jsonb_each_text(coalesce(p_gold_by, '{}'::jsonb))
     where key <> '' and coalesce(value::numeric, 0) > 0
    union
    select key
      from jsonb_object_keys(coalesce(p_donated_by, '{}'::jsonb)) as key
     where key <> ''
  ) donors;
$$;

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
    from public.guild_members
   where guild_id = p_guild
     and total_level >= 500;

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
  'Idempotent guild achievement unlocks from hall state and roster levels.';

revoke all on function public.guild_evaluate_achievements(uuid) from public, anon, authenticated;
grant execute on function public.guild_evaluate_achievements(uuid) to service_role;

revoke all on function public.guild_hall_tier_material_cost(text) from public, anon, authenticated;
grant execute on function public.guild_hall_tier_material_cost(text) to service_role;

revoke all on function public.guild_hall_materials_spent(jsonb) from public, anon, authenticated;
grant execute on function public.guild_hall_materials_spent(jsonb) to service_role;

revoke all on function public.guild_donor_count(jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.guild_donor_count(jsonb, jsonb) to service_role;

create or replace function public.guild_members_evaluate_achievements()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.guild_evaluate_achievements(coalesce(new.guild_id, old.guild_id));
  return coalesce(new, old);
end;
$$;

revoke all on function public.guild_members_evaluate_achievements() from public, anon, authenticated;
grant execute on function public.guild_members_evaluate_achievements() to service_role;

drop trigger if exists guild_members_evaluate_achievements on public.guild_members;
create trigger guild_members_evaluate_achievements
  after insert or update of total_level, guild_id on public.guild_members
  for each row
  execute function public.guild_members_evaluate_achievements();

create or replace function public.guild_banner_normalized(p_guild uuid, p_banner jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_bg text;
  v_accent text;
  v_emblem text;
  v_border text;
  v_palette text[] := array[
    'slate','midnight','wine','rust','ivory','ash','indigo','ocean','ember','plum'
  ];
  v_emblem_ok boolean;
  v_border_ok boolean;
begin
  v_bg := coalesce(p_banner ->> 'background', 'slate');
  v_accent := coalesce(p_banner ->> 'accent', 'ivory');
  if v_bg <> all (v_palette) or v_accent <> all (v_palette) then
    raise exception 'That colour is not on the banner palette.' using errcode = 'P0001';
  end if;
  v_emblem := nullif(p_banner ->> 'emblem', '');
  v_border := nullif(p_banner ->> 'border', '');
  if v_emblem is not null then
    select exists (
      select 1
        from public.guild_achievements a
       where a.guild_id = p_guild
         and a.achievement_id in (
           'gach_foundations','gach_hall_2','gach_hall_3','gach_hall_4',
           'gach_hall_arcana','gach_hall_5','gach_gold_100k','gach_gold_500k'
         )
         and case a.achievement_id
           when 'gach_foundations' then 'emblem_foundations'
           when 'gach_hall_2' then 'emblem_counting'
           when 'gach_hall_3' then 'emblem_boxing'
           when 'gach_hall_4' then 'emblem_garden'
           when 'gach_hall_arcana' then 'emblem_arcana'
           when 'gach_hall_5' then 'emblem_cage'
           when 'gach_gold_100k' then 'emblem_pockets'
           when 'gach_gold_500k' then 'emblem_deeper_pockets'
         end = v_emblem
    ) into v_emblem_ok;
    if not coalesce(v_emblem_ok, false) then
      raise exception 'That emblem is not unlocked.' using errcode = 'P0001';
    end if;
  end if;
  if v_border is not null then
    select exists (
      select 1
        from public.guild_achievements a
       where a.guild_id = p_guild
         and a.achievement_id in (
           'gach_materials','gach_donors_10','gach_donors_25','gach_rising_strength'
         )
         and case a.achievement_id
           when 'gach_materials' then 'border_vault'
           when 'gach_donors_10' then 'border_hands'
           when 'gach_donors_25' then 'border_more_hands'
           when 'gach_rising_strength' then 'border_strength'
         end = v_border
    ) into v_border_ok;
    if not coalesce(v_border_ok, false) then
      raise exception 'That border is not unlocked.' using errcode = 'P0001';
    end if;
  end if;
  return jsonb_build_object(
    'background', v_bg,
    'accent', v_accent,
    'emblem', to_jsonb(v_emblem),
    'border', to_jsonb(v_border)
  );
end;
$$;

revoke all on function public.guild_banner_normalized(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.guild_banner_normalized(uuid, jsonb) to service_role;

create or replace function public.guilds_require_valid_banner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.banner := public.guild_banner_normalized(new.id, coalesce(new.banner, '{}'::jsonb));
  return new;
end;
$$;

revoke all on function public.guilds_require_valid_banner() from public, anon, authenticated;
grant execute on function public.guilds_require_valid_banner() to service_role;

drop trigger if exists guilds_require_valid_banner on public.guilds;
create trigger guilds_require_valid_banner
  before insert or update of banner on public.guilds
  for each row
  execute function public.guilds_require_valid_banner();

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
    when others then
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

create or replace function public.guild_hall_apply_save_deltas(
  p_before jsonb,
  p_after jsonb,
  p_current jsonb,
  p_proposed jsonb,
  p_user_id uuid
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_taken numeric;
  v_remaining numeric;
  v_gold numeric;
  v_by jsonb;
  v_donated_by jsonb;
  v_donated_any boolean := false;
  v_store jsonb;
  v_bank jsonb;
  v_prev_inv jsonb;
  v_next_inv jsonb;
  v_old_bank jsonb;
  v_prop_bank jsonb;
  v_old_store jsonb;
  v_prop_store jsonb;
  v_key text;
  v_item_id text;
  v_ench text;
  v_sep text := chr(31);
  v_lost numeric;
  v_gained numeric;
  v_bank_gain numeric;
  v_bank_loss numeric;
  v_donated numeric;
  v_withdrawn numeric;
  v_settled jsonb;
begin
  v_remaining := greatest(
    0,
    1000000 - greatest(0, coalesce((p_current ->> 'gold_contributed')::numeric, 0))
  );
  v_taken := public.guild_hall_gold_taken_from_saves(p_before, p_after);
  if v_taken > v_remaining then
    return jsonb_build_object(
      'ok', false,
      'reason', case
        when v_remaining <= 0 then 'The gold total is already at its cap.'
        else 'That would go past the gold cap.'
      end
    );
  end if;
  v_gold := least(
    1000000,
    greatest(0, coalesce((p_current ->> 'gold_contributed')::numeric, 0)) + v_taken
  );
  v_by := coalesce(p_current -> 'gold_contributed_by', '{}'::jsonb);
  if jsonb_typeof(v_by) <> 'object' then
    v_by := '{}'::jsonb;
  end if;
  v_donated_by := coalesce(p_current -> 'donated_by', '{}'::jsonb);
  if jsonb_typeof(v_donated_by) <> 'object' then
    v_donated_by := '{}'::jsonb;
  end if;
  if v_taken > 0 and p_user_id is not null then
    v_donated_any := true;
    v_by := jsonb_set(
      v_by,
      array[p_user_id::text],
      to_jsonb(coalesce((v_by ->> p_user_id::text)::numeric, 0) + v_taken)
    );
  end if;

  v_store := coalesce(p_current -> 'storehouse', '[]'::jsonb);
  v_bank := coalesce(p_current -> 'bank_items', '[]'::jsonb);
  v_prev_inv := public.guild_hall_qty_map(p_before -> 'inventory');
  v_next_inv := public.guild_hall_qty_map(p_after -> 'inventory');
  v_old_bank := public.guild_hall_qty_map(p_current -> 'bank_items');
  v_prop_bank := public.guild_hall_qty_map(coalesce(p_proposed -> 'bank_items', p_current -> 'bank_items'));
  v_old_store := public.guild_hall_qty_map(p_current -> 'storehouse');
  v_prop_store := public.guild_hall_qty_map(coalesce(p_proposed -> 'storehouse', p_current -> 'storehouse'));

  for v_key in
    select distinct k from (
      select jsonb_object_keys(v_prev_inv) as k
      union
      select jsonb_object_keys(v_next_inv)
      union
      select jsonb_object_keys(v_old_bank)
      union
      select jsonb_object_keys(v_prop_bank)
      union
      select jsonb_object_keys(v_old_store)
      union
      select jsonb_object_keys(v_prop_store)
    ) keys
  loop
    v_lost := greatest(0, coalesce((v_prev_inv ->> v_key)::numeric, 0) - coalesce((v_next_inv ->> v_key)::numeric, 0));
    v_gained := greatest(0, coalesce((v_next_inv ->> v_key)::numeric, 0) - coalesce((v_prev_inv ->> v_key)::numeric, 0));
    v_bank_gain := least(
      greatest(0, coalesce((v_prop_bank ->> v_key)::numeric, 0) - coalesce((v_old_bank ->> v_key)::numeric, 0)),
      v_lost
    );
    v_bank_loss := least(
      greatest(0, coalesce((v_old_bank ->> v_key)::numeric, 0) - coalesce((v_prop_bank ->> v_key)::numeric, 0)),
      v_gained
    );
    if coalesce((v_prop_bank ->> v_key)::numeric, 0)
       is distinct from (coalesce((v_old_bank ->> v_key)::numeric, 0) + v_bank_gain - v_bank_loss) then
      return jsonb_build_object(
        'ok', false,
        'reason', 'The guild bank change did not match the save.'
      );
    end if;
    v_donated := v_lost - v_bank_gain;
    v_withdrawn := least(
      v_gained - v_bank_loss,
      greatest(0, coalesce((v_old_store ->> v_key)::numeric, 0) - coalesce((v_prop_store ->> v_key)::numeric, 0))
    );
    v_item_id := split_part(v_key, v_sep, 1);
    v_ench := split_part(v_key, v_sep, 2);
    if v_donated > 0 then
      v_donated_any := true;
      v_store := public.guild_hall_add_store_stack(v_store, v_item_id, v_donated, v_ench);
    end if;
    if v_withdrawn > 0 then
      v_store := public.guild_hall_take_store_stack(v_store, v_item_id, v_withdrawn, v_ench);
    end if;
  end loop;

  if v_donated_any and p_user_id is not null then
    v_donated_by := jsonb_set(v_donated_by, array[p_user_id::text], 'true'::jsonb);
  end if;

  v_bank := coalesce(p_proposed -> 'bank_items', v_bank);

  v_settled := public.guild_hall_settle_tiers(
    v_store,
    coalesce(p_current -> 'completed_tiers', '[]'::jsonb),
    v_gold
  );

  return jsonb_build_object(
    'ok', true,
    'gold_taken', v_taken,
    'gold_contributed', v_gold,
    'gold_contributed_by', v_by,
    'donated_by', v_donated_by,
    'storehouse', v_settled -> 'storehouse',
    'completed_tiers', v_settled -> 'completed_tiers',
    'bank_items', v_bank
  );
end;
$$;

create or replace function public.guild_commit_hall(
  p_user_id uuid,
  p_expected_save_version integer,
  p_expected_hall_revision bigint,
  p_payload jsonb,
  p_rng_state bigint,
  p_now timestamptz,
  p_hall jsonb,
  p_before jsonb,
  p_log jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member public.guild_members;
  v_hall public.guild_halls;
  v_old_version integer;
  v_version integer;
  v_applied jsonb;
  v_gold numeric;
  v_taken numeric;
  v_entry jsonb;
  v_unlocked jsonb;
begin
  if p_user_id is null then
    return jsonb_build_object('ok', false, 'reason', 'Sign in first.');
  end if;
  if p_before is null then
    return jsonb_build_object('ok', false, 'reason', 'Caught-up save missing.');
  end if;

  select * into v_member
    from public.guild_members
   where user_id = p_user_id
   limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'Join a guild first.');
  end if;

  select * into v_hall
    from public.guild_halls
   where guild_id = v_member.guild_id
   for update;
  if not found then
    insert into public.guild_halls (guild_id) values (v_member.guild_id)
    on conflict (guild_id) do nothing;
    select * into v_hall
      from public.guild_halls
     where guild_id = v_member.guild_id
     for update;
  end if;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'Guild hall not found.');
  end if;

  if coalesce(p_expected_hall_revision, 0) is distinct from coalesce(v_hall.hall_revision, 0) then
    return jsonb_build_object('ok', false, 'conflict', 'hall', 'reason', 'Hall changed. Sync and retry.');
  end if;

  select version
    into v_old_version
    from public.player_saves
   where user_id = p_user_id
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'conflict', 'save', 'reason', 'Save version conflict. Sync and retry.');
  end if;
  if v_old_version is distinct from p_expected_save_version then
    return jsonb_build_object('ok', false, 'conflict', 'save', 'reason', 'Save version conflict. Sync and retry.');
  end if;

  v_applied := public.guild_hall_apply_save_deltas(
    p_before,
    p_payload,
    jsonb_build_object(
      'gold_contributed', v_hall.gold_contributed,
      'gold_contributed_by', v_hall.gold_contributed_by,
      'donated_by', v_hall.donated_by,
      'storehouse', v_hall.storehouse,
      'completed_tiers', v_hall.completed_tiers,
      'bank_items', v_hall.bank_items
    ),
    coalesce(p_hall, '{}'::jsonb),
    p_user_id
  );
  if coalesce((v_applied ->> 'ok')::boolean, false) is not true then
    return jsonb_build_object(
      'ok', false,
      'reason', coalesce(v_applied ->> 'reason', 'Could not update the hall.')
    );
  end if;
  v_gold := coalesce((v_applied ->> 'gold_contributed')::numeric, 0);
  v_taken := coalesce((v_applied ->> 'gold_taken')::numeric, 0);

  update public.player_saves
     set payload = p_payload,
         version = p_expected_save_version + 1,
         advanced_to = p_now,
         rng_state = p_rng_state,
         updated_at = p_now
   where user_id = p_user_id
     and version = p_expected_save_version
  returning version into v_version;

  if v_version is null then
    return jsonb_build_object('ok', false, 'conflict', 'save', 'reason', 'Save version conflict. Sync and retry.');
  end if;

  update public.guild_halls
     set gold_contributed = v_gold,
         gold_contributed_by = coalesce(v_applied -> 'gold_contributed_by', gold_contributed_by),
         donated_by = coalesce(v_applied -> 'donated_by', donated_by),
         debt_remaining = greatest(0, 1000000 - v_gold),
         debt_paid_off = v_gold >= 1000000,
         debt_paid_by = coalesce(v_applied -> 'gold_contributed_by', gold_contributed_by),
         storehouse = coalesce(v_applied -> 'storehouse', storehouse),
         completed_tiers = coalesce(v_applied -> 'completed_tiers', completed_tiers),
         bank_items = coalesce(v_applied -> 'bank_items', bank_items),
         hall_revision = coalesce(hall_revision, 0) + 1,
         updated_at = p_now
   where guild_id = v_member.guild_id
  returning * into v_hall;

  if jsonb_typeof(p_log) = 'array' then
    for v_entry in
      select * from jsonb_array_elements(public.guild_hall_stamp_log_gold(p_log, v_taken))
    loop
      perform public.guild_append_log(v_member.guild_id, v_entry);
    end loop;
  end if;

  v_unlocked := public.guild_evaluate_achievements(v_member.guild_id);

  return jsonb_build_object(
    'ok', true,
    'version', v_version,
    'hall_revision', v_hall.hall_revision,
    'gold_taken', v_taken,
    'gold_contributed', v_gold,
    'completed_tiers', v_hall.completed_tiers,
    'unlocked_now', coalesce(v_unlocked, '[]'::jsonb)
  );
end;
$$;

revoke all on function public.guild_commit_hall(uuid, integer, bigint, jsonb, bigint, timestamptz, jsonb, jsonb, jsonb)
  from public, anon, authenticated;
grant execute on function public.guild_commit_hall(uuid, integer, bigint, jsonb, bigint, timestamptz, jsonb, jsonb, jsonb)
  to service_role;

notify pgrst, 'reload schema';
