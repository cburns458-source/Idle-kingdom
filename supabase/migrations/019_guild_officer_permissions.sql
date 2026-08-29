-- Officers may accept or decline applications and remove guests.
-- Only the leader may change settings, ranks, or roster members.

drop policy if exists "guilds update by managers" on public.guilds;
create policy "guilds update by leader" on public.guilds
  for update using (auth.uid() = leader_id) with check (auth.uid() = leader_id);

drop policy if exists "guild members update" on public.guild_members;
create policy "guild members update" on public.guild_members
  for update
  using (
    auth.uid() = user_id
    or auth.uid() = (select leader_id from public.guilds where id = guild_id)
  )
  with check (
    auth.uid() = user_id
    or auth.uid() = (select leader_id from public.guilds where id = guild_id)
  );

drop policy if exists "guild members delete" on public.guild_members;
create policy "guild members delete" on public.guild_members
  for delete using (
    auth.uid() = user_id
    or auth.uid() = (select leader_id from public.guilds where id = guild_id)
  );
