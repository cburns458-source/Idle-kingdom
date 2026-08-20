-- Authoritative wall clock for login catch-up (device clocks cannot invent AFK time).
create or replace function public.server_now_ms()
returns bigint
language sql
stable
as $$
  select (extract(epoch from clock_timestamp()) * 1000)::bigint;
$$;

grant execute on function public.server_now_ms() to anon, authenticated;
