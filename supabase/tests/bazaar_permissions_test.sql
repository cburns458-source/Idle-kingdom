-- What a signed-in client may not touch.
--
-- Row level security with no policies is one door; the grants are the other. A
-- player who could call `bazaar_place_order` could hand it a save with the gold
-- already added, so the routines are the exchange, not an interface to it.
\pset pager off

set role authenticated;

\echo '--- a signed-in client reading the book directly ---'
do $$ begin
  perform 1 from public.bazaar_orders;
  raise exception 'authenticated could read bazaar_orders';
exception when insufficient_privilege then raise notice 'denied: %', sqlerrm;
end $$;
\echo '--- and calling the routines directly ---'
do $$ begin
  perform public.bazaar_place_order('11111111-1111-1111-1111-111111111111','x','buy','ITEM-0001',1,1,'{}'::jsonb, now());
  raise exception 'authenticated could place an order';
exception when insufficient_privilege then raise notice 'denied: %', sqlerrm;
end $$;
do $$ begin
  perform public.bazaar_settle_collect('11111111-1111-1111-1111-111111111111', array[gen_random_uuid()], '{}'::jsonb, now());
  raise exception 'authenticated could settle a claim';
exception when insufficient_privilege then raise notice 'denied: %', sqlerrm;
end $$;
do $$ begin
  perform public.bazaar_cancel_order('11111111-1111-1111-1111-111111111111', gen_random_uuid());
  raise exception 'authenticated could cancel an order';
exception when insufficient_privilege then raise notice 'denied: %', sqlerrm;
end $$;
reset role;
\echo '--- the service role can ---'
set role service_role;
select count(*) as orders_visible_to_service_role from public.bazaar_orders;
reset role;
