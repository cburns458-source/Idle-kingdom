-- The exchange writes a save through a trigger that guards which device may.
--
-- `player_saves_require_active_session` refuses a write whose play session is not
-- the account's active one, and it works that out from `auth.uid()`. The edge
-- function holds a service key, which carries no subject, so the trigger finds no
-- profile to check against and stands aside. This is that, checked, because the
-- other outcome is every offer refused on any account that has claimed a seat.
\pset pager off

insert into auth.users (id) values ('44444444-4444-4444-4444-444444444444')
  on conflict do nothing;

insert into public.profiles (user_id, active_play_session_id)
values ('44444444-4444-4444-4444-444444444444', '33333333-3333-3333-3333-333333333333')
on conflict (user_id) do update set active_play_session_id = excluded.active_play_session_id;

insert into public.player_saves (user_id, save_version, updated_at, payload, play_session_id)
values (
  '44444444-4444-4444-4444-444444444444', 7, '2026-05-01T00:00:00Z',
  '{"saveVersion":7,"updatedAt":"2026-05-01T00:00:00.000Z","gold":500,"inventory":[]}',
  '33333333-3333-3333-3333-333333333333'
)
on conflict (user_id) do update
   set updated_at = excluded.updated_at,
       payload = excluded.payload,
       play_session_id = excluded.play_session_id;

select public.bazaar_place_order(
  '44444444-4444-4444-4444-444444444444', 'Seated', 'buy', 'ITEM-0500', 10, 1,
  '{"saveVersion":7,"updatedAt":"2026-05-01T00:00:01.000Z","gold":490,"inventory":[]}',
  '2026-05-01T00:00:00Z'
) -> 'order' -> 'status' as with_a_claimed_seat;
