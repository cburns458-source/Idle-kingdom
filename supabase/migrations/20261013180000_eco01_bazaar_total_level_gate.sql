-- ECO-01: new Bazaar offers require total level 200.
--
-- Total level is the sum of every skill level on the owner's stored save,
-- matching `totalLevel` in `src/game/skills/totals.ts` and
-- `packages/ik_rules/lib/src/skills/totals.dart`. This only rejects INSERT
-- of a new `bazaar_orders` row. Updates (fills), cancellations, and
-- collection are not gated, so offers that already exist keep running.

create or replace function public.bazaar_payload_total_level(p_payload jsonb)
returns integer
language sql
immutable
set search_path = public
as $$
  select coalesce((
    select sum(coalesce((skill->>'level')::numeric, 0))::integer
      from jsonb_array_elements(
        case
          when jsonb_typeof(p_payload -> 'skills') = 'array' then p_payload -> 'skills'
          else '[]'::jsonb
        end
      ) as skill
  ), 0);
$$;

comment on function public.bazaar_payload_total_level(jsonb) is
  'Sum of skill levels on a save payload, matching the game totalLevel helper.';

create or replace function public.bazaar_user_total_level(p_user_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select public.bazaar_payload_total_level(s.payload)
    from public.player_saves s
   where s.user_id = p_user_id;
$$;

comment on function public.bazaar_user_total_level(uuid) is
  'Owner total level from player_saves.payload, used by the Bazaar insert gate.';

create or replace function public.bazaar_orders_require_total_level()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total integer;
begin
  v_total := coalesce(public.bazaar_user_total_level(new.user_id), 0);
  if v_total < 200 then
    raise exception 'BAZAAR_TOTAL_LEVEL required=200 totalLevel=%', v_total;
  end if;
  return new;
end;
$$;

comment on function public.bazaar_orders_require_total_level() is
  'ECO-01 backstop: refuse INSERT of a new Bazaar offer below total level 200.';

drop trigger if exists bazaar_orders_require_total_level on public.bazaar_orders;
create trigger bazaar_orders_require_total_level
  before insert on public.bazaar_orders
  for each row
  execute function public.bazaar_orders_require_total_level();

revoke all on function public.bazaar_payload_total_level(jsonb)
  from public, anon, authenticated;
revoke all on function public.bazaar_user_total_level(uuid)
  from public, anon, authenticated;
revoke all on function public.bazaar_orders_require_total_level()
  from public, anon, authenticated;

grant execute on function public.bazaar_payload_total_level(jsonb) to service_role;
grant execute on function public.bazaar_user_total_level(uuid) to service_role;
grant execute on function public.bazaar_orders_require_total_level() to service_role;
