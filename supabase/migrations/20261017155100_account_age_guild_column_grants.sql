-- Follow-up: table-level SELECT still covered the locked columns after
-- 20261017155000's column REVOKE. Replace those grants. TEST only.

revoke select on public.guilds from anon, authenticated;
grant select (
  id, name, tag, emblem, leader_id, created_at, join_policy,
  rank_labels, rank_icon_theme, guest_auto_accept,
  skill_milestone_settings, permissions, banner
) on public.guilds to anon, authenticated;

revoke select on public.guild_applications from anon, authenticated;
grant select (
  id, guild_id, user_id, username, created_at, guest
) on public.guild_applications to anon, authenticated;

revoke all on function public.guilds_description_requires_chat() from public, anon, authenticated;

notify pgrst, 'reload schema';
