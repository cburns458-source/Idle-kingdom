-- BUG-02: cancel open Bazaar orders for items now marked Tradeable false.
--
-- Machete (ITEM-0406), Excavator's Pickaxe (ITEM-0313), Stolen Coin Purse
-- (ITEM-0299) and Beggar's Hood (ITEM-0300) are quest-only rewards and can no
-- longer be listed or bid on. Each open order goes through
-- bazaar_cancel_order, so a sell order's remaining items and a buy order's
-- escrowed gold land in bazaar_collect with reason 'cancelled', the same as a
-- player cancelling it themselves. Filled trades are left alone.
--
-- Apply only after the bazaar function that refuses these items is deployed to
-- the same project, so no new order slips in afterwards. Safe to re-run: a
-- second pass finds nothing open.
do $$
declare
  v_order record;
  v_count integer := 0;
begin
  for v_order in
    select id, user_id, side, item_id
      from public.bazaar_orders
     where status = 'open'
       and item_id in ('ITEM-0406', 'ITEM-0313', 'ITEM-0299', 'ITEM-0300')
     order by created_at
       for update
  loop
    perform public.bazaar_cancel_order(v_order.user_id, v_order.id);
    v_count := v_count + 1;
    raise notice 'BUG-02 cancelled % order % (%) for user %',
      v_order.side, v_order.id, v_order.item_id, v_order.user_id;
  end loop;
  raise notice 'BUG-02 cancelled % open Bazaar order(s) for untradeable items', v_count;
end $$;
