-- ECO: pin an empty search_path on the Bazaar total-level functions.
--
-- 20261013180000_eco01_bazaar_total_level_gate.sql created these with
-- `set search_path = public`. Their bodies already name every object with its
-- schema (public.player_saves, public.bazaar_payload_total_level,
-- public.bazaar_user_total_level) or use pg_catalog built-ins only, so an
-- empty search_path changes nothing at runtime and removes the
-- security-definer search-path risk flagged by the Supabase advisor.
--
-- Rollback (do not run as part of apply):
--   alter function public.bazaar_user_total_level(uuid) set search_path = public;
--   alter function public.bazaar_payload_total_level(jsonb) set search_path = public;
--   alter function public.bazaar_orders_require_total_level() set search_path = public;

alter function public.bazaar_user_total_level(uuid) set search_path = '';
alter function public.bazaar_payload_total_level(jsonb) set search_path = '';
alter function public.bazaar_orders_require_total_level() set search_path = '';
