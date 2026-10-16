-- Guild hall writes take gold and materials from the save delta.
--
-- guild_commit_hall used to write p_hall.gold_contributed (capped at 1M) and
-- p_hall.completed_tiers as-is. A modified client that reached this RPC could
-- unlock every room without paying. The running total is now gold the save
-- lost between p_before (caught-up, immediately before the hall command) and
-- p_payload. Storehouse stacks are items that left that bag (and did not go
-- into the bank). Tiers settle here from that gold and those stacks. Claimed
-- totals are ignored. Gold past the 1M cap and a mismatched bank are refused
-- rather than truncated or kept.

create or replace function public.guild_hall_gold_taken_from_saves(p_before jsonb, p_after jsonb)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select greatest(
    0,
    trunc(coalesce((p_before ->> 'gold')::numeric, 0))
    - trunc(coalesce((p_after ->> 'gold')::numeric, 0))
  );
$$;

comment on function public.guild_hall_gold_taken_from_saves(jsonb, jsonb) is
  'Gold the hosted save actually lost. Never a client-sent running total.';

revoke all on function public.guild_hall_gold_taken_from_saves(jsonb, jsonb)
  from public, anon, authenticated;
grant execute on function public.guild_hall_gold_taken_from_saves(jsonb, jsonb) to service_role;

create or replace function public.guild_hall_qty_map(p_items jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(k, q), '{}'::jsonb)
  from (
    select
      coalesce(item ->> 'itemId', '') || chr(31) || coalesce(item ->> 'enchantmentId', '') as k,
      sum(greatest(0, trunc(coalesce((item ->> 'quantity')::numeric, 0)))) as q
    from jsonb_array_elements(
      case when jsonb_typeof(p_items) = 'array' then p_items else '[]'::jsonb end
    ) item
    where coalesce(item ->> 'itemId', '') <> ''
    group by 1
  ) summed;
$$;

revoke all on function public.guild_hall_qty_map(jsonb) from public, anon, authenticated;
grant execute on function public.guild_hall_qty_map(jsonb) to service_role;

create or replace function public.guild_hall_add_store_stack(
  p_store jsonb,
  p_item_id text,
  p_qty numeric,
  p_enchantment text
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_store jsonb := case when jsonb_typeof(p_store) = 'array' then p_store else '[]'::jsonb end;
  v_next jsonb := '[]'::jsonb;
  v_row jsonb;
  v_merged boolean := false;
  v_want numeric := greatest(0, trunc(coalesce(p_qty, 0)));
begin
  if v_want <= 0 or coalesce(p_item_id, '') = '' then
    return v_store;
  end if;
  if coalesce(p_enchantment, '') <> '' then
    return v_store || jsonb_build_array(jsonb_build_object(
      'itemId', p_item_id,
      'quantity', v_want,
      'enchantmentId', p_enchantment
    ));
  end if;
  for v_row in select * from jsonb_array_elements(v_store)
  loop
    if not v_merged
       and (v_row ->> 'itemId') = p_item_id
       and coalesce(v_row ->> 'enchantmentId', '') = '' then
      v_next := v_next || jsonb_build_array(jsonb_set(
        v_row,
        '{quantity}',
        to_jsonb(coalesce((v_row ->> 'quantity')::numeric, 0) + v_want)
      ));
      v_merged := true;
    else
      v_next := v_next || jsonb_build_array(v_row);
    end if;
  end loop;
  if not v_merged then
    v_next := v_next || jsonb_build_array(jsonb_build_object('itemId', p_item_id, 'quantity', v_want));
  end if;
  return v_next;
end;
$$;

revoke all on function public.guild_hall_add_store_stack(jsonb, text, numeric, text)
  from public, anon, authenticated;
grant execute on function public.guild_hall_add_store_stack(jsonb, text, numeric, text) to service_role;

create or replace function public.guild_hall_take_store_stack(
  p_store jsonb,
  p_item_id text,
  p_qty numeric,
  p_enchantment text
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_store jsonb := case when jsonb_typeof(p_store) = 'array' then p_store else '[]'::jsonb end;
  v_next jsonb := '[]'::jsonb;
  v_row jsonb;
  v_have numeric;
  v_owed numeric := greatest(0, trunc(coalesce(p_qty, 0)));
begin
  if v_owed <= 0 then
    return v_store;
  end if;
  for v_row in select * from jsonb_array_elements(v_store)
  loop
    if v_owed > 0
       and (v_row ->> 'itemId') = p_item_id
       and (
         p_enchantment is null
         or coalesce(v_row ->> 'enchantmentId', '') = coalesce(p_enchantment, '')
       ) then
      v_have := coalesce((v_row ->> 'quantity')::numeric, 0);
      if v_owed >= v_have then
        v_owed := v_owed - v_have;
      else
        v_next := v_next || jsonb_build_array(jsonb_set(v_row, '{quantity}', to_jsonb(v_have - v_owed)));
        v_owed := 0;
      end if;
    else
      v_next := v_next || jsonb_build_array(v_row);
    end if;
  end loop;
  return v_next;
end;
$$;

revoke all on function public.guild_hall_take_store_stack(jsonb, text, numeric, text)
  from public, anon, authenticated;
grant execute on function public.guild_hall_take_store_stack(jsonb, text, numeric, text) to service_role;

create or replace function public.guild_hall_store_has(
  p_store jsonb,
  p_item_id text,
  p_qty numeric
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(sum(coalesce((item ->> 'quantity')::numeric, 0)), 0) >= coalesce(p_qty, 0)
  from jsonb_array_elements(
    case when jsonb_typeof(p_store) = 'array' then p_store else '[]'::jsonb end
  ) item
  where (item ->> 'itemId') = p_item_id;
$$;

revoke all on function public.guild_hall_store_has(jsonb, text, numeric)
  from public, anon, authenticated;
grant execute on function public.guild_hall_store_has(jsonb, text, numeric) to service_role;

create or replace function public.guild_hall_settle_tiers(
  p_store jsonb,
  p_done jsonb,
  p_gold numeric
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_store jsonb := case when jsonb_typeof(p_store) = 'array' then p_store else '[]'::jsonb end;
  v_done jsonb := case when jsonb_typeof(p_done) = 'array' then p_done else '[]'::jsonb end;
  v_gold numeric := greatest(0, coalesce(p_gold, 0));
  v_tiers jsonb :=
    '[
      {"id":"build_the_hall","gold":0,"cost":[{"itemId":"ITEM-0015","quantity":1000},{"itemId":"ITEM-0095","quantity":100}]},
      {"id":"hall_bank","gold":10000,"cost":[{"itemId":"ITEM-0017","quantity":24000},{"itemId":"ITEM-0002","quantity":10000},{"itemId":"ITEM-0006","quantity":6320}]},
      {"id":"hall_boxing_ring","gold":40000,"cost":[{"itemId":"ITEM-0002","quantity":14000},{"itemId":"ITEM-0095","quantity":13160},{"itemId":"ITEM-0017","quantity":13160}]},
      {"id":"hall_indoor_garden","gold":130000,"cost":[{"itemId":"ITEM-0016","quantity":20000},{"itemId":"ITEM-0002","quantity":8320},{"itemId":"ITEM-0377","quantity":12000}]},
      {"id":"hall_arcana_station","gold":400000,"cost":[{"itemId":"ITEM-0011","quantity":16000},{"itemId":"ITEM-0018","quantity":16000},{"itemId":"ITEM-0002","quantity":8320}]},
      {"id":"hall_monster_cage","gold":1000000,"cost":[{"itemId":"ITEM-0077","quantity":10000},{"itemId":"ITEM-0076","quantity":12000},{"itemId":"ITEM-0006","quantity":18320}]}
    ]'::jsonb;
  v_tier jsonb;
  v_cost jsonb;
  v_id text;
  v_ok boolean;
begin
  loop
    v_tier := null;
    for v_cost in select * from jsonb_array_elements(v_tiers)
    loop
      v_id := v_cost ->> 'id';
      if not exists (
        select 1
          from jsonb_array_elements_text(v_done) done
         where done = v_id
      ) then
        v_tier := v_cost;
        exit;
      end if;
    end loop;
    if v_tier is null then
      exit;
    end if;
    if v_gold < coalesce((v_tier ->> 'gold')::numeric, 0) then
      exit;
    end if;
    v_ok := true;
    for v_cost in select * from jsonb_array_elements(v_tier -> 'cost')
    loop
      if not public.guild_hall_store_has(v_store, v_cost ->> 'itemId', coalesce((v_cost ->> 'quantity')::numeric, 0)) then
        v_ok := false;
        exit;
      end if;
    end loop;
    if not v_ok then
      exit;
    end if;
    for v_cost in select * from jsonb_array_elements(v_tier -> 'cost')
    loop
      v_store := public.guild_hall_take_store_stack(
        v_store,
        v_cost ->> 'itemId',
        coalesce((v_cost ->> 'quantity')::numeric, 0),
        null
      );
    end loop;
    v_done := v_done || jsonb_build_array(v_tier ->> 'id');
  end loop;
  return jsonb_build_object('storehouse', v_store, 'completed_tiers', v_done);
end;
$$;

revoke all on function public.guild_hall_settle_tiers(jsonb, jsonb, numeric)
  from public, anon, authenticated;
grant execute on function public.guild_hall_settle_tiers(jsonb, jsonb, numeric) to service_role;

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
  if v_taken > 0 and p_user_id is not null then
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
      v_store := public.guild_hall_add_store_stack(v_store, v_item_id, v_donated, v_ench);
    end if;
    if v_withdrawn > 0 then
      v_store := public.guild_hall_take_store_stack(v_store, v_item_id, v_withdrawn, v_ench);
    end if;
  end loop;

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
    'storehouse', v_settled -> 'storehouse',
    'completed_tiers', v_settled -> 'completed_tiers',
    'bank_items', v_bank
  );
end;
$$;

comment on function public.guild_hall_apply_save_deltas(jsonb, jsonb, jsonb, jsonb, uuid) is
  'Hall gold, storehouse, and tiers from the caught-up save versus the post-command save. Ignores claimed gold_contributed and completed_tiers. Refuses over-cap gold and a mismatched bank.';

revoke all on function public.guild_hall_apply_save_deltas(jsonb, jsonb, jsonb, jsonb, uuid)
  from public, anon, authenticated;
grant execute on function public.guild_hall_apply_save_deltas(jsonb, jsonb, jsonb, jsonb, uuid)
  to service_role;

drop function if exists public.guild_commit_hall(uuid, integer, bigint, jsonb, bigint, timestamptz, jsonb, jsonb);

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
    for v_entry in select * from jsonb_array_elements(p_log)
    loop
      if coalesce(v_entry ->> 'kind', '') = 'donation' then
        v_entry := jsonb_set(coalesce(v_entry, '{}'::jsonb), '{gold}', to_jsonb(v_taken));
      end if;
      perform public.guild_append_log(v_member.guild_id, v_entry);
    end loop;
  end if;

  return jsonb_build_object(
    'ok', true,
    'version', v_version,
    'hall_revision', v_hall.hall_revision,
    'gold_taken', v_taken,
    'gold_contributed', v_gold,
    'completed_tiers', v_hall.completed_tiers
  );
end;
$$;

revoke all on function public.guild_commit_hall(uuid, integer, bigint, jsonb, bigint, timestamptz, jsonb, jsonb, jsonb)
  from public, anon, authenticated;
grant execute on function public.guild_commit_hall(uuid, integer, bigint, jsonb, bigint, timestamptz, jsonb, jsonb, jsonb)
  to service_role;
