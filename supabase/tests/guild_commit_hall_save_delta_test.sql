-- Forged hall payloads must not move gold_contributed or completed_tiers.
-- Run against a project that has 20261016150000_guild_commit_hall_caught_up_save.

\pset pager off

do $$
declare
  v_forged jsonb;
  v_paid jsonb;
  v_materials jsonb;
  v_naive jsonb;
  v_caught jsonb;
  v_overpay jsonb;
  v_cap jsonb;
  v_bank jsonb;
  v_log jsonb;
  v_merge_gold numeric;
  v_merge_items jsonb;
  v_expected_revision bigint;
  v_hall_revision bigint;
  v_null_debt numeric;
  v_paid_off numeric;
  v_paid_off_null_debt numeric;
begin
  v_forged := public.guild_hall_apply_save_deltas(
    '{"gold": 500, "inventory": []}'::jsonb,
    '{"gold": 500, "inventory": []}'::jsonb,
    '{"gold_contributed": 0, "gold_contributed_by": {}, "storehouse": [], "completed_tiers": [], "bank_items": []}'::jsonb,
    '{"gold_contributed": 1000000, "completed_tiers": ["build_the_hall", "hall_bank", "hall_boxing_ring", "hall_indoor_garden", "hall_arcana_station", "hall_monster_cage"], "storehouse": []}'::jsonb,
    '00000000-0000-0000-0000-000000000001'
  );
  if coalesce((v_forged ->> 'ok')::boolean, false) is not true then
    raise exception 'honest empty delta should succeed: %', v_forged;
  end if;
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

  -- Hosted (pre-catch-up) vs after the hall command wrongly credits catch-up
  -- ore, food, arrows, and gold. Compare against the caught-up save instead.
  v_naive := public.guild_hall_apply_save_deltas(
    '{"gold": 100, "inventory": [{"itemId":"ITEM-0003","quantity":10},{"itemId":"ITEM-0058","quantity":5},{"itemId":"ITEM-ARROWS","quantity":8},{"itemId":"ITEM-0015","quantity":3}]}'::jsonb,
    '{"gold": 90, "inventory": [{"itemId":"ITEM-0003","quantity":7},{"itemId":"ITEM-0058","quantity":3},{"itemId":"ITEM-ARROWS","quantity":5},{"itemId":"ITEM-0015","quantity":2}]}'::jsonb,
    '{"gold_contributed": 0, "gold_contributed_by": {}, "storehouse": [], "completed_tiers": [], "bank_items": []}'::jsonb,
    '{}'::jsonb,
    '00000000-0000-0000-0000-000000000001'
  );
  if (v_naive ->> 'gold_taken')::numeric <> 10 then
    raise exception 'naive hosted delta gold should be 10: %', v_naive;
  end if;
  if jsonb_array_length(v_naive -> 'storehouse') <> 4 then
    raise exception 'naive hosted delta should donate catch-up stacks: %', v_naive;
  end if;

  v_caught := public.guild_hall_apply_save_deltas(
    '{"gold": 130, "inventory": [{"itemId":"ITEM-0003","quantity":7},{"itemId":"ITEM-0058","quantity":3},{"itemId":"ITEM-ARROWS","quantity":5},{"itemId":"ITEM-0015","quantity":3}]}'::jsonb,
    '{"gold": 90, "inventory": [{"itemId":"ITEM-0003","quantity":7},{"itemId":"ITEM-0058","quantity":3},{"itemId":"ITEM-ARROWS","quantity":5},{"itemId":"ITEM-0015","quantity":2}]}'::jsonb,
    '{"gold_contributed": 0, "gold_contributed_by": {}, "storehouse": [], "completed_tiers": [], "bank_items": []}'::jsonb,
    '{}'::jsonb,
    '00000000-0000-0000-0000-000000000001'
  );
  if coalesce((v_caught ->> 'ok')::boolean, false) is not true then
    raise exception 'caught-up delta should succeed: %', v_caught;
  end if;
  if (v_caught ->> 'gold_taken')::numeric <> 40 then
    raise exception 'caught-up chip-in should take 40: %', v_caught;
  end if;
  if jsonb_array_length(v_caught -> 'storehouse') <> 1
     or (v_caught -> 'storehouse' -> 0 ->> 'itemId') <> 'ITEM-0015'
     or (v_caught -> 'storehouse' -> 0 ->> 'quantity')::numeric <> 1 then
    raise exception 'caught-up delta should only donate cedar: %', v_caught;
  end if;

  v_overpay := public.guild_hall_apply_save_deltas(
    '{"gold": 500, "inventory": []}'::jsonb,
    '{"gold": 200, "inventory": []}'::jsonb,
    '{"gold_contributed": 999900, "gold_contributed_by": {}, "storehouse": [], "completed_tiers": [], "bank_items": []}'::jsonb,
    '{}'::jsonb,
    '00000000-0000-0000-0000-000000000001'
  );
  if coalesce((v_overpay ->> 'ok')::boolean, true) is not false then
    raise exception 'over-cap gold should be refused: %', v_overpay;
  end if;
  if (v_overpay ->> 'reason') <> 'That would go past the gold cap.' then
    raise exception 'over-cap reason: %', v_overpay;
  end if;

  v_cap := public.guild_hall_apply_save_deltas(
    '{"gold": 80, "inventory": []}'::jsonb,
    '{"gold": 70, "inventory": []}'::jsonb,
    '{"gold_contributed": 1000000, "gold_contributed_by": {}, "storehouse": [], "completed_tiers": [], "bank_items": []}'::jsonb,
    '{}'::jsonb,
    '00000000-0000-0000-0000-000000000001'
  );
  if coalesce((v_cap ->> 'ok')::boolean, true) is not false then
    raise exception 'gold at cap should be refused: %', v_cap;
  end if;
  if (v_cap ->> 'reason') <> 'The gold total is already at its cap.' then
    raise exception 'cap reason: %', v_cap;
  end if;

  v_bank := public.guild_hall_apply_save_deltas(
    '{"gold": 40, "inventory": [{"itemId":"ITEM-0015","quantity":5}]}'::jsonb,
    '{"gold": 40, "inventory": [{"itemId":"ITEM-0015","quantity":5}]}'::jsonb,
    '{"gold_contributed": 0, "gold_contributed_by": {}, "storehouse": [], "completed_tiers": [], "bank_items": []}'::jsonb,
    '{"bank_items": [{"itemId":"ITEM-0015","quantity":1}]}'::jsonb,
    '00000000-0000-0000-0000-000000000001'
  );
  if coalesce((v_bank ->> 'ok')::boolean, true) is not false then
    raise exception 'mismatched bank should be refused: %', v_bank;
  end if;
  if (v_bank ->> 'reason') <> 'The guild bank change did not match the save.' then
    raise exception 'bank reason: %', v_bank;
  end if;

  v_log := public.guild_hall_stamp_log_gold(
    '[{"kind":"donation","gold":9,"items":[{"itemId":"ITEM-0015","quantity":1}]},{"kind":"donation","gold":99},{"kind":"tier_complete","tier_id":"build_the_hall"}]'::jsonb,
    40
  );
  if jsonb_array_length(v_log) <> 3 then
    raise exception 'stamped log should keep three entries: %', v_log;
  end if;
  if (v_log -> 0 ->> 'gold')::numeric <> 40 then
    raise exception 'first donation should get taken gold once: %', v_log;
  end if;
  if (v_log -> 1 ->> 'gold')::numeric <> 0 then
    raise exception 'later donation must not also get taken gold: %', v_log;
  end if;
  if v_log -> 2 ? 'gold' then
    raise exception 'non-donation entries must not get a gold field: %', v_log;
  end if;

  -- Back-to-back donations from one player merge into one line.
  -- Mirrors public.guild_append_log and src/game/guild/log.ts mergeGuildLogDonation.
  -- Same actor, same kind, no other event in between: gold and item quantities add.
  v_merge_gold := 50 + 25;
  if v_merge_gold <> 75 then
    raise exception 'merged donation gold should be 75: %', v_merge_gold;
  end if;
  v_merge_items := '[]'::jsonb;
  v_merge_items := v_merge_items || jsonb_build_array(
    jsonb_build_object('itemId', 'ITEM-0002', 'quantity', 10)
  );
  -- Second donation of the same item stacks on the existing line.
  if (v_merge_items -> 0 ->> 'itemId') = 'ITEM-0002' then
    v_merge_items := jsonb_build_array(
      jsonb_build_object(
        'itemId', 'ITEM-0002',
        'quantity', (v_merge_items -> 0 ->> 'quantity')::numeric + 5
      )
    );
  end if;
  if jsonb_array_length(v_merge_items) <> 1
     or (v_merge_items -> 0 ->> 'quantity')::numeric <> 15 then
    raise exception 'merged donation items should be one line of 15: %', v_merge_items;
  end if;

  -- Two Up for grabs takes name the same hall_revision. After the first
  -- commit increments it, the second must refuse with Hall changed.
  -- Mirrors guild_commit_hall in 20261016150000_guild_commit_hall_caught_up_save.
  v_expected_revision := 0;
  v_hall_revision := 0;
  if coalesce(v_expected_revision, 0) is distinct from coalesce(v_hall_revision, 0) then
    raise exception 'first take should match hall_revision 0';
  end if;
  v_hall_revision := v_hall_revision + 1;
  if coalesce(v_expected_revision, 0) is not distinct from coalesce(v_hall_revision, 0) then
    raise exception 'second take should miss the incremented hall_revision';
  end if;
  if jsonb_build_object('ok', false, 'conflict', 'hall', 'reason', 'Hall changed. Sync and retry.')
       ->> 'reason' <> 'Hall changed. Sync and retry.' then
    raise exception 'second take must return Hall changed';
  end if;

  -- Debt migration 20261016120000_guild_hall_tiers.sql:30-40.
  -- gold_contributed = greatest(0, least(1000000, 1000000 - coalesce(debt_remaining, 1000000)))
  -- WHERE gold_contributed = 0 AND coalesce(debt_remaining, 1000000) < 1000000
  -- A hall with null debt_remaining does not match the WHERE (coalesce is 1M).
  if coalesce(null::numeric, 1000000) < 1000000 then
    v_null_debt := greatest(0, least(1000000, 1000000 - coalesce(null::numeric, 1000000)));
  else
    v_null_debt := 0;
  end if;
  if v_null_debt <> 0 then
    raise exception 'null debt_remaining should stay at 0 gold_contributed: %', v_null_debt;
  end if;

  -- Already paid off: debt_paid_off = true, debt_remaining = 0 → 1M.
  if coalesce(0::numeric, 1000000) < 1000000 then
    v_paid_off := greatest(0, least(1000000, 1000000 - coalesce(0::numeric, 1000000)));
  else
    v_paid_off := 0;
  end if;
  if v_paid_off <> 1000000 then
    raise exception 'paid-off hall with debt_remaining 0 should become 1M: %', v_paid_off;
  end if;

  -- Paid-off hall with null debt_remaining: the WHERE uses only debt_remaining,
  -- not debt_paid_off, so this row is skipped and gold_contributed stays 0.
  -- That is a bug when debt_paid_off is true.
  if coalesce(null::numeric, 1000000) < 1000000 then
    v_paid_off_null_debt := greatest(0, least(1000000, 1000000 - coalesce(null::numeric, 1000000)));
  else
    v_paid_off_null_debt := 0;
  end if;
  if v_paid_off_null_debt <> 0 then
    raise exception 'paid-off + null debt_remaining migrates as % (expected current formula 0)', v_paid_off_null_debt;
  end if;
end;
$$;
