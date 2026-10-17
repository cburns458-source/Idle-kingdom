-- Trigger function is not an RPC. TEST only.

revoke all on function public.guilds_description_requires_chat() from public, anon, authenticated;

notify pgrst, 'reload schema';
