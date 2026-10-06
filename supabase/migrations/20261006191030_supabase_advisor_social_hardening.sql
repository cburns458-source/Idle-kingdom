-- Follow-up to 026: fix active client failures, make social authorization
-- enforce the product rules at the database boundary, and remove advisor
-- findings that represent real query work rather than intentional locks.

-- Foreign-key columns used by guild screens, profile joins, and reverse
-- block/mute checks need their own indexes. Primary keys cover the opposite
-- direction for player_blocks and player_mutes.
create index if not exists guild_projects_guild_id_idx
  on public.guild_projects (guild_id);
create index if not exists guild_challenges_guild_id_idx
  on public.guild_challenges (guild_id);
create index if not exists guild_applications_user_id_idx
  on public.guild_applications (user_id);
create index if not exists profiles_guild_id_idx
  on public.profiles (guild_id)
  where guild_id is not null;
create index if not exists player_blocks_blocked_user_id_idx
  on public.player_blocks (blocked_user_id);
create index if not exists player_mutes_muted_user_id_idx
  on public.player_mutes (muted_user_id);

-- These helpers are only called by the already-pinned Bazaar RPCs, but pin
-- their own lookup path too so their behavior cannot depend on caller state.
alter function public.bazaar_tax(bigint, bigint)
  set search_path = public;
alter function public.bazaar_note_price(text, bigint, bigint)
  set search_path = public;

-- A FOR ALL policy also participates in SELECT. Split the three mixed policies
-- so reads evaluate one policy, and cache auth.uid() once per statement.
drop policy if exists "profiles are owner readable" on public.profiles;
drop policy if exists "profiles are self-writable" on public.profiles;
create policy "profiles are owner readable" on public.profiles
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "profiles are self insert" on public.profiles
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "profiles are self update" on public.profiles
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "profiles are self delete" on public.profiles
  for delete to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "saves are self only" on public.player_saves;
create policy "saves are self only" on public.player_saves
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "leaderboards self upsert" on public.leaderboard_snapshots;
create policy "leaderboards self insert" on public.leaderboard_snapshots
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "leaderboards self update" on public.leaderboard_snapshots
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "leaderboards self delete" on public.leaderboard_snapshots
  for delete to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "presence readable by signed in" on public.activity_presence;
drop policy if exists "presence self write" on public.activity_presence;
create policy "presence readable by signed in" on public.activity_presence
  for select to authenticated
  using (true);
create policy "presence self insert" on public.activity_presence
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "presence self update" on public.activity_presence
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "presence self delete" on public.activity_presence
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- Global is shared, local requires a live presence at that location, guild
-- requires membership/guest access, and a DM key must contain an exact peer.
drop policy if exists "chat readable by participants" on public.chat_messages;
create policy "chat readable by participants" on public.chat_messages
  for select to authenticated
  using (
    channel_key = 'global'
    or (
      channel_key like 'local:%'
      and exists (
        select 1
          from public.activity_presence ap
         where ap.user_id = (select auth.uid())
           and ap.location_id = substr(channel_key, 7)
           and ap.expires_at > now()
      )
    )
    or (
      channel_key like 'guild:%'
      and (
        public.guild_role_of(
          nullif(substr(channel_key, 7), '')::uuid,
          (select auth.uid())
        ) is not null
        or exists (
          select 1
            from public.guild_guests gg
           where gg.guild_id = nullif(substr(channel_key, 7), '')::uuid
             and gg.user_id = (select auth.uid())
        )
      )
    )
    or (
      channel_key like 'dm:%'
      and split_part(substr(channel_key, 4), ':', 3) = ''
      and (
        split_part(substr(channel_key, 4), ':', 1) = (select auth.uid())::text
        or split_part(substr(channel_key, 4), ':', 2) = (select auth.uid())::text
      )
    )
  );

drop policy if exists "bounty claims insert self" on public.bounty_claims;
drop policy if exists "bounty claims readable by signed in" on public.bounty_claims;
create policy "bounty claims insert self" on public.bounty_claims
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "bounty claims readable by signed in" on public.bounty_claims
  for select to authenticated
  using (true);

-- A friendship may only be created by the recipient of a pending request.
-- Direct client inserts can no longer manufacture a friendship unilaterally.
drop policy if exists "friend requests readable" on public.friend_requests;
drop policy if exists "friend requests insert self" on public.friend_requests;
drop policy if exists "friend requests delete parties" on public.friend_requests;
create policy "friend requests readable" on public.friend_requests
  for select to authenticated
  using (
    (select auth.uid()) = from_user_id
    or (select auth.uid()) = to_user_id
  );
create policy "friend requests insert self" on public.friend_requests
  for insert to authenticated
  with check (
    (select auth.uid()) = from_user_id
    and from_user_id <> to_user_id
  );
create policy "friend requests delete parties" on public.friend_requests
  for delete to authenticated
  using (
    (select auth.uid()) = from_user_id
    or (select auth.uid()) = to_user_id
  );

drop policy if exists "friendships readable" on public.friendships;
drop policy if exists "friendships insert party" on public.friendships;
drop policy if exists "friendships delete party" on public.friendships;
create policy "friendships readable" on public.friendships
  for select to authenticated
  using (
    (select auth.uid()) = user_a
    or (select auth.uid()) = user_b
  );
create policy "friendships insert accepted request" on public.friendships
  for insert to authenticated
  with check (
    (
      (select auth.uid()) = user_a
      and exists (
        select 1
          from public.friend_requests fr
         where fr.from_user_id = user_b
           and fr.to_user_id = user_a
      )
    )
    or (
      (select auth.uid()) = user_b
      and exists (
        select 1
          from public.friend_requests fr
         where fr.from_user_id = user_a
           and fr.to_user_id = user_b
      )
    )
  );
create policy "friendships delete party" on public.friendships
  for delete to authenticated
  using (
    (select auth.uid()) = user_a
    or (select auth.uid()) = user_b
  );

drop policy if exists "guild applications readable" on public.guild_applications;
drop policy if exists "guild applications insert self" on public.guild_applications;
drop policy if exists "guild applications delete" on public.guild_applications;
create policy "guild applications readable" on public.guild_applications
  for select to authenticated
  using (
    (select auth.uid()) = user_id
    or public.is_guild_manager(guild_id)
  );
create policy "guild applications insert self" on public.guild_applications
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "guild applications delete" on public.guild_applications
  for delete to authenticated
  using (
    (select auth.uid()) = user_id
    or public.is_guild_manager(guild_id)
  );

drop policy if exists "guilds readable by signed in" on public.guilds;
drop policy if exists "guilds insert own" on public.guilds;
drop policy if exists "guilds update by managers" on public.guilds;
drop policy if exists "guilds delete by leader" on public.guilds;
create policy "guilds readable by signed in" on public.guilds
  for select to authenticated using (true);
create policy "guilds insert own" on public.guilds
  for insert to authenticated
  with check ((select auth.uid()) = leader_id);
create policy "guilds update by managers" on public.guilds
  for update to authenticated
  using (public.is_guild_manager(id))
  with check (public.is_guild_manager(id));
create policy "guilds delete by leader" on public.guilds
  for delete to authenticated
  using ((select auth.uid()) = leader_id);

drop policy if exists "guild members readable by signed in" on public.guild_members;
drop policy if exists "guild members insert" on public.guild_members;
drop policy if exists "guild members update" on public.guild_members;
drop policy if exists "guild members delete" on public.guild_members;
create policy "guild members readable by signed in" on public.guild_members
  for select to authenticated using (true);
create policy "guild members insert" on public.guild_members
  for insert to authenticated
  with check (
    public.is_guild_manager(guild_id)
    or (
      (select auth.uid()) = user_id
      and role = 'recruit'
      and exists (
        select 1 from public.guilds g
         where g.id = guild_id and g.join_policy = 'open'
      )
      and not exists (
        select 1 from public.guild_members m
         where m.user_id = (select auth.uid())
      )
    )
    or (
      (select auth.uid()) = user_id
      and role = 'leader'
      and exists (
        select 1 from public.guilds g
         where g.id = guild_id
           and g.leader_id = (select auth.uid())
      )
    )
  );
create policy "guild members update" on public.guild_members
  for update to authenticated
  using (
    (select auth.uid()) = user_id
    or (select auth.uid()) = (
      select leader_id from public.guilds where id = guild_id
    )
  )
  with check (
    (select auth.uid()) = user_id
    or (select auth.uid()) = (
      select leader_id from public.guilds where id = guild_id
    )
  );
create policy "guild members delete" on public.guild_members
  for delete to authenticated
  using (
    (select auth.uid()) = user_id
    or (select auth.uid()) = (
      select leader_id from public.guilds where id = guild_id
    )
  );

drop policy if exists "guild guests readable by signed in" on public.guild_guests;
drop policy if exists "guild guests insert" on public.guild_guests;
drop policy if exists "guild guests delete" on public.guild_guests;
create policy "guild guests readable by signed in" on public.guild_guests
  for select to authenticated using (true);
create policy "guild guests insert" on public.guild_guests
  for insert to authenticated
  with check (
    public.is_guild_manager(guild_id)
    or (
      (select auth.uid()) = user_id
      and exists (
        select 1 from public.guilds g
         where g.id = guild_id and g.guest_auto_accept
      )
      and not exists (
        select 1 from public.guild_guests gg
         where gg.user_id = (select auth.uid())
      )
    )
  );
create policy "guild guests delete" on public.guild_guests
  for delete to authenticated
  using (
    (select auth.uid()) = user_id
    or public.is_guild_manager(guild_id)
  );

drop policy if exists "guild projects readable by signed in" on public.guild_projects;
drop policy if exists "guild projects insert by managers" on public.guild_projects;
create policy "guild projects readable by signed in" on public.guild_projects
  for select to authenticated using (true);
create policy "guild projects insert by managers" on public.guild_projects
  for insert to authenticated
  with check (public.is_guild_manager(guild_id));

drop policy if exists "guild challenges readable by signed in" on public.guild_challenges;
drop policy if exists "guild challenges insert by managers" on public.guild_challenges;
create policy "guild challenges readable by signed in" on public.guild_challenges
  for select to authenticated using (true);
create policy "guild challenges insert by managers" on public.guild_challenges
  for insert to authenticated
  with check (public.is_guild_manager(guild_id));

drop policy if exists "guild halls readable by members" on public.guild_halls;
drop policy if exists "guild halls insert by managers" on public.guild_halls;
create policy "guild halls readable by members" on public.guild_halls
  for select to authenticated
  using (
    public.guild_role_of(guild_id, (select auth.uid())) is not null
  );
create policy "guild halls insert by managers" on public.guild_halls
  for insert to authenticated
  with check (public.is_guild_manager(guild_id));

drop policy if exists "pvp snapshots readable" on public.pvp_snapshots;
drop policy if exists "pvp snapshots insert self" on public.pvp_snapshots;
drop policy if exists "pvp snapshots update self" on public.pvp_snapshots;
create policy "pvp snapshots readable" on public.pvp_snapshots
  for select to authenticated using (true);
create policy "pvp snapshots insert self" on public.pvp_snapshots
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "pvp snapshots update self" on public.pvp_snapshots
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

comment on view public.public_profiles is
  'Intentional definer view: exposes only the public profile projection while the base row remains owner-only.';
comment on view public.guild_hall_tiers is
  'Intentional definer view: exposes tier progress while member-only hall inventory and debt details remain protected.';

notify pgrst, 'reload schema';
