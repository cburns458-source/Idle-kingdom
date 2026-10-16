-- Forged hall payloads must not move gold_contributed or completed_tiers.
-- Run against a project that has 20261016140000_guild_commit_hall_save_delta.

\pset pager off

do $$
declare
  v_forged jsonb;
  v_paid jsonb;
  v_materials jsonb;
begin
  v_forged := public.guild_hall_apply_save_deltas(
    '{"gold": 500, "inventory": []}'::jsonb,
    '{"gold": 500, "inventory": []}'::jsonb,
    '{"gold_contributed": 0, "gold_contributed_by": {}, "storehouse": [], "completed_tiers": [], "bank_items": []}'::jsonb,
    '{"gold_contributed": 1000000, "completed_tiers": ["build_the_hall", "hall_bank", "hall_boxing_ring", "hall_indoor_garden", "hall_arcana_station", "hall_monster_cage"], "storehouse": []}'::jsonb,
    '00000000-0000-0000-0000-000000000001'
  );
  if (v_forged ->> 'gold_taken')::numeric <> 0 then
    raise exception 'forged gold_contributed was credited: %', v_forged;
  end if;
  if (v_forged ->> 'gold_contributed')::numeric <> 0 then
    raise exception 'forged running total stuck: %', v_forged;
  end if;
  if jsonb_array_length(v_forged -> 'completed_tiers') <> 0 then
    raise exception 'forged completed_tiers stuck: %', v_forged;
  end if;

  v_paid := public.guild_hall_apply_save_deltas(
    '{"gold": 250, "inventory": []}'::jsonb,
    '{"gold": 200, "inventory": []}'::jsonb,
    '{"gold_contributed": 50, "gold_contributed_by": {}, "storehouse": [], "completed_tiers": [], "bank_items": []}'::jsonb,
    '{"gold_contributed": 1000000}'::jsonb,
    '00000000-0000-0000-0000-000000000001'
  );
  if (v_paid ->> 'gold_taken')::numeric <> 50 then
    raise exception 'save gold delta was not 50: %', v_paid;
  end if;
  if (v_paid ->> 'gold_contributed')::numeric <> 100 then
    raise exception 'running total should be 100: %', v_paid;
  end if;

  v_materials := public.guild_hall_apply_save_deltas(
    '{"gold": 0, "inventory": [{"itemId":"ITEM-0015","quantity":1000},{"itemId":"ITEM-0095","quantity":100}]}'::jsonb,
    '{"gold": 0, "inventory": []}'::jsonb,
    '{"gold_contributed": 0, "gold_contributed_by": {}, "storehouse": [], "completed_tiers": [], "bank_items": []}'::jsonb,
    '{"completed_tiers": ["build_the_hall", "hall_bank"], "storehouse": []}'::jsonb,
    '00000000-0000-0000-0000-000000000001'
  );
  if v_materials -> 'completed_tiers' <> '["build_the_hall"]'::jsonb then
    raise exception 'build the hall should settle from donated stacks: %', v_materials;
  end if;
  if jsonb_array_length(v_materials -> 'storehouse') <> 0 then
    raise exception 'build the hall should spend its materials: %', v_materials;
  end if;

  if public.guild_hall_gold_taken_from_saves('{"gold":80}'::jsonb, '{"gold":80}'::jsonb) <> 0 then
    raise exception 'unchanged gold must take nothing';
  end if;
  if public.guild_hall_gold_taken_from_saves('{"gold":80}'::jsonb, '{"gold":30}'::jsonb) <> 50 then
    raise exception 'gold taken should be 50';
  end if;
end;
$$;
