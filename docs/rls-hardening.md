# RLS hardening (migration 026)

Closes the privilege-escalation and over-sharing gaps the Supabase advisor
flagged, matching the access model agreed for Idle Kingdoms.

## What 026 changes

- **Profiles:** base table is owner-only. `public_profiles` exposes public
  fields; hidden gear blanks `equipment_json`. Session seat and rename cooldown
  stay off the public view.
- **Presence:** signed-in reads only. `share_location_with_friends` is a real
  column (nearby peers still see you at the same spot).
- **Chat:** signed-in, channel-scoped reads. Client inserts removed; only
  `send-chat` writes. Cooldown / block / mute / report tables locked to
  `service_role`.
- **Leaderboards:** still publicly readable (anon) via `leaderboard_entries`
  joined to `public_profiles`.
- **Guilds:** signed-in browse. Members cannot self-promote or rewrite
  `guild_id`. Open join is recruit-only. Projects/challenges/halls are no longer
  freely writable; additive RPCs handle contribute / pay debt / donate.
- **Guild halls:** full row for members; `guild_hall_tiers` exposes
  `completed_tiers` + `debt_paid_off` to signed-in browsers.
- **Bazaar message board:** client policies removed (product removed).
- **Saves:** refuse an upload stamped older than the server row.
- **search_path:** pinned on `server_now_ms` and the play-session trigger.

## Manual steps (you)

Migrations are **not** auto-applied. Edge functions deploy from `test-launch`.

1. **Paste SQL in Supabase → SQL Editor** (project for test-launch), in order if
   not already applied:
   - Everything through `025_bazaar_six_slots.sql` (if a fresh project)
   - Then the full contents of `supabase/migrations/026_rls_hardening.sql`
2. **Confirm** in Table Editor / Advisors:
   - `public_profiles` and `guild_hall_tiers` exist
   - `chat_messages` has no insert policy for `authenticated`
   - Advisor “RLS enabled no policy” for bazaar market + moderation tables is
     expected (revoked from clients)
3. **Auth → Attack Protection:** enable **Leaked password protection**
   (HaveIBeenPwned). Not a migration.
4. **Deploy edge functions:** merge/push this branch to `test-launch`, or run
   the Deploy workflow. `send-chat` must be live before players rely on the new
   DM / cooldown checks.
5. **Smoke in the live game** (signed-in):
   - Open another player’s profile (gear hidden when they hid it)
   - Browse guilds / member list
   - Open your guild hall (storehouse visible) vs another guild (tiers only)
   - Send global chat; confirm DM only with a real peer
   - Contribute to a guild project

A copy of `026_rls_hardening.sql` is also under `/opt/cursor/artifacts/` on the
agent for easy download.

## Follow-up changes (do not forget)

### Economy / authority

1. **Server-authoritative game simulation** — client-trusted saves are the root
   of item/gold duplication (including market + guild donations). Long-term the
   server should run or validate progression, not only store blobs.
2. **Save writes with expected `updated_at`** — tighten client upserts to the
   same equality check the Bazaar RPCs use (026 only blocks older stamps).
3. **Guild hall donations that debit the cloud save in one transaction** —
   today the RPC adds storehouse stock while the client removes bag items;
   a modified client can donate without paying.
4. **Guild hall tier settlement on the server** — completing tiers / spending
   storehouse materials must not be client-decided.
5. **Guild hall withdrawals** — role-gated RPC once leader permission settings
   exist (no withdrawal API yet).
6. **Per-rank guild permission settings** — plug into one server-side
   `guild_may(actor, guild, action)` used by all guild RPCs (hall functions,
   withdrawals, settings).

### Social / moderation

7. **Hosted blocks, mutes, reports** — wire Flutter/web to the locked tables;
   `send-chat` already checks `player_blocks` when rows exist.
8. **Report payload includes message id / body** — so dashboard review works.
9. **Chat disabled flag after slurs** — persist account mute server-side
   (client filter alone is bypassable).
10. **Remove bazaar message-board UI** — `bazaar_posts` is locked; Flutter
    Citadel “Message board” still calls it until a client PR removes it.
11. **Drop or archive `bazaar_posts`** — after UI removal, drop table or keep
    read-only for history.

### Profiles / privacy cleanup

12. **Remove dead `privacy_public_skills`** — column + `setPrivacyPublicSkills`
    + local/demo paths; skills stay public for leaderboards.
13. **Stop embedding `shareLocationWithFriends` only in `appearance_json`** —
    once all clients write the real presence column, drop the JSON fallback.
14. **Username uniqueness via RPC** — avoid listing all public usernames to
    check renames (privacy + scale).

### Guild UX / RPC completeness

15. **`guild_create` / `guild_join_open` / `accept_application` RPCs** — move
    remaining multi-step client writes fully server-side (026 hardened policies
    but create/join still use direct inserts under tighter checks).
16. **Project/challenge seeding only from server** — founders currently insert
    as managers; prefer one create-guild RPC.
17. **Public guild card fields** — if you want non-members to see more than
    hall tiers (e.g. member count already works via roster read).

### Ops

18. **Re-run Supabase Security Advisor** after 026 and confirm only expected
    “no policy” tables remain.
19. **Document third-party leaderboard access** — anon `leaderboard_entries` is
    intentional; note rate limits / caching if sites appear.
