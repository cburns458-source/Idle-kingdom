-- BUG-02: cancel open Bazaar orders for the Dwarven Warhammer (ITEM-0123).
--
-- The warhammer is now the quest-only reward for Forged in Fire (QST-0007) and
-- is marked Tradeable false, so it can no longer be listed or bid on. Each open
-- order goes through bazaar_cancel_order, so a sell order's remaining items and
-- a buy order's escrowed gold land in bazaar_collect with reason 'cancelled',
-- the same as a player cancelling it themselves. Filled trades are left alone.
--
-- Apply only after the build that marks the warhammer untradeable (#314) is
-- deployed to the same project, so no new order slips in afterwards. Safe to
-- re-run: a second pass finds nothing open.
do $$
declare
  v_order record;
  v_count integer := 0;
begin
  for v_order in
    select id, user_id, side, item_id
      from public.bazaar_orders
     where status = 'open'
       and item_id = 'ITEM-0123'
     order by created_at
       for update
  loop
    perform public.bazaar_cancel_order(v_order.user_id, v_order.id);
    v_count := v_count + 1;
    raise notice 'BUG-02 cancelled % order % (%) for user %',
      v_order.side, v_order.id, v_order.item_id, v_order.user_id;
  end loop;
  raise notice 'BUG-02 cancelled % open Bazaar order(s) for the Dwarven Warhammer', v_count;
end $$;
