# Restoria master backlog

**Status: Approved by Conor on 2026-10-12. Updated 2026-10-15 (Conor).**

This is the single master backlog for Restoria. Only Conor edits it, or a PR he
approves. Every design call stays with Conor. Work on any item still follows
[AGENT_WORKFLOW.md](AGENT_WORKFLOW.md): plan, stop for Conor's OK, then a PR into
`test-launch`. No bot ever touches `main`.

Sources behind the first version: `AGENTS.md`, `docs/AGENT_WORKFLOW.md`,
`docs/Master_Prompt.md`, `docs/deployment.md`, `docs/rls-hardening.md`,
`docs/server-authority.md`, `docs/bazaar-api.md`,
`content/data/game-database.json` (test-launch), the quest rules in
`packages/ik_rules/lib/src/quests/*` and `src/game/quests/*`, and PRs #283–#302.

Contents:

1. [How to use this file](#1-how-to-use-this-file)
2. [Decisions log](#2-decisions-log)
3. [Open questions register](#3-open-questions-register)
4. [Now / Next / Later board](#4-now--next--later-board)
5. [Category sections](#5-category-sections)
6. [Done archive](#6-done-archive)
7. [Appendix A: Fennel "Getting Started" bug analysis](#appendix-a-fennel-getting-started-bug-analysis)
8. [Appendix B: Specialist bots](#appendix-b-specialist-bots)

---

## 1. How to use this file

### 1.1 ID scheme

Each item has a category prefix and a number, e.g. `ARC-01`. IDs are never
reused or renumbered. Gaps in the numbering are intentional. Open questions use
`OQ-##`.

| Prefix | Section | Covers |
|---|---|---|
| ADM | Admin / Ops / Security | Supabase, Cloudflare, RLS, email, dashboard, telemetry |
| BUG | Bugs and fixes | Anything that's broken or exploitable |
| QST | Quests and dialogue | Quests, tutorial, NPC dialogue |
| SYS | Core systems | Dialogue engine, travel, inventory, defense, notifications plumbing |
| ARC | Arcana / Enchanting / Essence / Spells | Tablets, essence, spell charges, enchantments |
| ITM | Items and gear | New items, armor sets, ammo, blessings |
| SKL | Skills and activities | Thievery, cooking, fishing tides, fruit trees, success chance |
| ECO | Economy and rewards | Bazaar gates, plaza points, shops, sell rules |
| SOC | Social / Competitive | Guilds, guild hall, leaderboards, PvP, mass bosses |
| MAP | World and maps | Region map, isles, citadel, landing nodes |
| WLD | Lore / World / Races / Religion | Religion rework, kingdom lore |
| UI | UI / UX | Menus, icons, fonts, color rules, tabs, language |
| ART | Art direction and animation | Asset specs, Flame animations, log panels |
| TTL | Titles | Prefix/suffix titles |
| MEM | Membership | QoL perks, pricing |
| NTF | Notifications | Event list and delivery |
| DNG | Dungeons / Group content | Catacombs |

### 1.2 Status legend

Only these statuses:

`Inbox` → `Needs Clarification` → `Ready for Proposal` → `Awaiting Approval` →
`Approved for Implementation` → `In Progress` → `Review` →
`Staging Verification` → `Awaiting Merge Approval` → `Merged` → `Verified`.
Or `Blocked` / `Rejected`.

**Rule:** an item can't move past `Needs Clarification` while it has an open
`OQ-##`.

### 1.3 Priority legend

| Priority | Meaning |
|---|---|
| **P0** | Now: security, exploits, broken onboarding |
| **P1** | Next |
| **P2** | After |
| **Later** | Large or speculative; needs decisions or new infrastructure first |
| Unset (Vari to decide) | No priority has been decided yet |

### 1.4 Fields per item

| Field | Example |
|---|---|
| **ID** | `ARC-01` |
| **Title** (Conor's wording) | "Change enchantments to create tablets…" |
| **Category** | ARC |
| **Description** | One or two sentences from existing notes or title context |
| **Status** | see 1.2 |
| **Readiness** | Whether work can start, from existing text only |
| **Priority** | P0 / P1 / P2 / Later / Unset (Vari to decide) |
| **Depends on** | IDs (hard) · *soft:* IDs |
| **Blocks** | IDs |
| **Overlaps / duplicates** | IDs |
| **Open questions** | `OQ-##` links |
| **Owner bot** | Short name from the [AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) roster (see [Appendix B](#appendix-b-specialist-bots)) |
| **Acceptance criteria** | What "done" means. Unknown: `TBD (owner to propose)` |
| **Next action** | Immediate next step, only when existing text supports one |
| **Repo touchpoints** | files/tables already involved |
| **Links** | PRs, Discord, playtest notes |

The category tables in section 5 carry Status, Readiness, Priority, Owner, and
Next action as columns. Description and Acceptance criteria go in Notes, with
blocks, overlaps, repo touchpoints and links.

### 1.5 Moving items

- When Conor rules on something, add a dated row to the decisions log. Rows are
  immutable once written; a reversal is a new row.
- When an `OQ-##` is answered, record the answer in the decisions log, mark the
  question resolved, and move the items it blocked forward.
- When an item lands on `test-launch`, move it to the done archive with its PR
  and date (Conor, 2026-10-13: the Done list tracks test-launch; `main` later).

---

## 2. Decisions log

Conor's rulings, dated. Immutable once written.

| Date | Decision | Evidence |
|---|---|---|
| 2026-10-15 | Guild hall: every tier is a week of solo gathering (about 40,320 items per tier, Eco's Reading B costs) | Vari (Conor) |
| 2026-10-15 | Guild hall gold: one running total that members chip into, replacing the 1M hall debt. Tiers unlock at 10k, 40k, 130k, 400k and 1M once their materials are in | Vari (Conor) |
| 2026-10-15 | Goblins start with the Wooden Dagger and no shield | Vari (Conor) |
| 2026-10-15 | The Cow fight is unchanged | Vari (Conor) |
| 2026-10-15 | Tutorial flow (QST-02 / OQ-09 / SYS-01): partway players are locked back into the tutorial (keep progress and items; idle actions and travel in hidden places stop; Bazaar orders kept); finished players unchanged; not skippable; locked places hidden until unlocked; mobile-style guidance (hovering pointer, dimmed screen, only the target tappable; falls back to dialogue with no dim if the target is missing); first 5 potato gathers guaranteed one potato each, no other drops; first 5 cooks guaranteed success; Fennel only looks at potatoes; final step is fight a Cow in the pasture (never a bull); Fennel tells the player to equip the starting sword and shield, no gear gift; losing leaves the step open to retry; if the player dies on the Cow step with no food, Fennel gives 5 cooked potatoes, server-checked once per death; killing the Cow stops combat, ends the quest, farewell plays, and the world opens immediately; Quest keeps existing lines and only adds or fixes where needed | Vari (Conor); In Progress on `sys/tutorial-flow` |
| 2026-10-15 | Bots message Vari in their own 1:1 for a go; a group-chat agreement is not a go | Vari (Conor); `docs/AGENT_WORKFLOW.md` |
| 2026-10-15 | Game Bible Regular Bow lines removed | Vari (Conor); PR #383 |
| 2026-10-15 | Workflow doc: Cursor cloud agents for commits, pushes, and migrations | PR #384 |
| 2026-10-15 | BUG-01, BUG-02, and BUG-04 Verified on test.restoriaidle.com | Conor playtest; BUG-01 #304, BUG-02 #310 (Tradeable column; not #377), BUG-04 #333 |
| 2026-10-13 | Done archive tracks `test-launch`; `main` is updated later | Conor |
| 2026-10-13 | Inventory/bank caps: 84 bag slots / 168 bank slots | PR #332, Conor (OQ-03 / SYS-03) |
| 2026-10-13 | Travel stays instant; remove the unused travel-time setting (no player-facing change) | Conor (SYS-07) |
| 2026-10-13 | QST-01 closed (Getting Started / Green Thumb dialogue) | PR #323, #270 |
| 2026-10-13 | BUG-03 (todo drops/recipes) closed: solved before tracking | Conor; no fixing PR in `git log` |
| 2026-10-13 | Ranked PvP reward exploit closed (server-authoritative payouts) | PR #333 (BUG-04) |
| 2026-10-12 | Region unlocks by total level at 200 / 400 / 800; regions not implemented yet (on hold for map assets). Whether existing quest unlocks also stay is undecided | Conor (OQ-11; still Open) |
| 2026-10-12 | This backlog (structure, items, IDs, priorities, owner bots) approved | Conor |
| ≤ 2026-10-12 | Workflow: plan → owner OK → PR into `test-launch` → playtest → Conor merges to `main` | `AGENTS.md`, `docs/AGENT_WORKFLOW.md` (PR #299) |
| ≤ 2026-10-12 | Server-authoritative saves: the `game` edge function is the only writer of `player_saves` | `docs/server-authority.md` |
| 2026-10-12 | Enchanted gear sells at Wizard's Shop (2×) and general merchants (1×), not at the Bazaar | PR #301, merged 2026-10-12 08:14 PT (on test-launch; PR #302 promotes to main) |
| ≤ 2026-10-12 | Location art spec: square sources that crop to portrait | `docs/Master_Prompt.md` §6 |
| ≤ 2026-10-12 | Confirm email is OFF on purpose (turning it on breaks character creation) | `docs/deployment.md`; see ADM-02 |
| 2026-10-13 | Travel is instant except the delays below (30 s death pause, hostile-area confirm / under-level forced combat, optional walk animation, 150 ms network spinner). No timed travel mechanic. | Conor (OQ-01 / SYS-02) |
| 2026-10-13 | Game Systems cleanup: Game Bible bag/bank caps aligned to 84/168; SYS-02 marked Answered; capacity drift test imports TS constants (Dart/edge sources still read). Travel rulings stay as the two existing log rows. | PR #354 |

### 2.1 Standing context (facts that shape open items)

- ⚠️ Combat now has HP **and** DR (Damage Resistance): PR #289 "Retune enemy
  base HP and add Damage Resistance". Affects OQ-04.
- ⚠️ Travel is instant except these delays: 30 s death pause, hostile-area
  confirm / under-level forced combat, optional walk animation (off by default),
  and the 150 ms network spinner. Timed travel was removed (`remove-timed-travel`).
  Unused travel-time setting cleanup is SYS-07 (#336; approved 2026-10-13).
- ⚠️ Items that already exist: Quiver (back slot, Artisanry 15), 9 bows, no
  arrows, Enchanting Tablet + Spell Tablet (Crafting → consumed by Arcana), one
  Essence item (harnessed at Wizard's Tower), Chromium and Vanadium ore/bars,
  Lockpicks, Temple "blessing" amenity (overheal), Goblin Camp, Giant Camp,
  Abandoned Mineshaft (`game-database.json`).
- ⚠️ Vesper (race change) = miniquest "A Change of Skin", total level 500,
  repeatable every 7 days (QST-0009, NPC-0016).
- "Untradeable" is the Items `Tradeable` column (BUG-02). False keeps an item
  off the Bazaar only; shops still buy anything with `Base Sell Value > 0`.
  PR #301 *deliberately* lets enchanted gear sell at shops.
- ⚠️ Guild hall (2026-10-15): each tier is a week of solo gathering (~40,320
  items, Eco Reading B costs). Gold is one running total members chip into
  (replaces the 1M hall debt). Tiers unlock at 10k / 40k / 130k / 400k / 1M
  once their materials are in.
- ⚠️ Goblins start with the Wooden Dagger and no shield (2026-10-15). The Cow
  fight is unchanged.

**Guardrail from `Master_Prompt.md` §2:** "Do not add currencies, energy
systems, monetization systems… not defined by the supplied sources." Plaza
points (ECO-03), membership (MEM-\*), and essence-as-charge (ARC-03) each need
Conor to update the Game Bible/DB first, or agents will refuse or stall.

---

## 3. Open questions register

Conor decides. Open unless marked answered. OQ-03, OQ-05, and OQ-09 are answered; OQ-11 stays Open with a partial ruling.

### 3.1 Conor's own

| ID | Question | Blocks | Context found | Status |
|---|---|---|---|---|
| OQ-01 | Should moving between locations be a mechanic, or instant? | MAP-01, MAP-04, SYS-02 | Answered 2026-10-13 (Conor): instant. Travel is instant except these delays: death pause, hostile-area confirm, optional walk animation, loading spinner. Dead travel-duration constant removed. See decisions log 2026-10-13 (OQ-01 / SYS-02 / SYS-07). | Answered |
| OQ-02 | Should bows require arrows? | ITM-03, ITM-04 | 9 bows, Quiver gives a Hunting XP factor, no arrow items | Open |
| OQ-03 | Maximum inventory size? | SYS-03, UI-12, MEM-01, NTF-02 | No inventory cap key in Config; shipped as 84 bag / 168 bank | Answered 2026-10-13 (Conor): 84 bag slots / 168 bank slots (#332) |
| OQ-04 | Defense, or just health? | SYS-04, ARC-07, ARC-08 | DR already shipped in #289, so the question is really "keep DR as the defense stat?" | Open |

### 3.2 Found while building the backlog

| ID | Question | Blocks | Answer | Status |
|---|---|---|---|---|
| OQ-05 | What does "untradeable" mean? Quest items, uniques (Excavator's Pickaxe sells for 69), starter cosmetics (Traveler's Tunic 24), enchanted gear? Should it be an explicit DB column? | BUG-02, QST-12, ARC-01 | Can't be listed on the Bazaar, still sells to shops; untradeable iff its only source is quest rewards; Golden Spud stays tradeable; enchanted Bazaar block unchanged. Items `Tradeable` column. | Answered 2026-10-12 (Conor) |
| OQ-06 | Membership: price, one-time or subscription, and is it fair? "Instant Bazaar at total level 1" and "double AFK" are close to pay-to-win in a game with a shared market and leaderboards. | MEM-\* | — | Open |
| OQ-07 | Religion vs races: replace races fully? What happens to existing race bonuses, race starting items, Vesper, "A Change of Skin", and the Pureblooded title? | WLD-01, TTL-03 | — | Open |
| OQ-08 | Mass bosses: which bosses? What are the scaling and contribution formulas? Are there server-side lobbies (new realtime infra)? | SOC-04 | — | Open |
| OQ-09 | Mandatory tutorial: what happens to existing players partway through Getting Started, and to players who already finished it? | QST-02 | Answered 2026-10-15 (Vari / Conor): partway players locked back in (keep progress/items; idle actions/travel in hidden places stop; Bazaar orders kept); finished players unchanged. See decisions log. Implementation In Progress on #386 / `sys/tutorial-flow`. | Answered |
| OQ-10 | Bazaar gate at total level 200: what about existing players under 200 who have live offers? | ECO-01 | — | Open |
| OQ-11 | Region unlocks (200/400/800 total level) vs the existing quest-based unlocks (Through the Thicket, Going Deeper, Forged in Fire). Which wins? | MAP-01, MAP-01b | Conor confirmed total-level region unlock thresholds 200 / 400 / 800 (regions unlock by total level, decided Oct 12, 2026); regions are not implemented yet, so it is on hold until map assets arrive. Whether existing quest unlocks also stay is undecided. | Open |
| OQ-12 | Back slot conflict: blessings, the Quiver/Hunter's Quiver, and capes all want the Back slot. | ITM-01, ITM-04 | — | Open |
| OQ-13 | Spell charging: does the 1/150 per-action loss stack with "only spent on relevant actions"? What happens to existing spells? | ARC-03 | — | Open |
| OQ-14 | Tablet rework migration: what happens to enchanted items players already own, and to recipes they've learned? | ARC-01 | — | Open |
| OQ-15 | Plaza points: can they be traded? Do bounties keep any gold? What goes in the shop's item and XP catalog? | ECO-03 | — | Open |
| OQ-16 | Telemetry: what do you want to measure, which vendor, and what privacy/consent rules? | ADM-05 | — | Open |
| OQ-17 | Catacombs: solo survival, group roles, or both first? | DNG-01 | — | Open |
| OQ-18 | Language support: which languages, and when? (Copy is in the DB plus hardcoded Dart strings.) | UI-14 | — | Open |

---

## 4. Now / Next / Later board

Just IDs, in order. Conor re-orders this.

### P0: Now (security, exploits, broken onboarding)

1. **ADM-01** Supabase/Cloudflare/RLS audit. Re-run advisors, do leaked-password protection, close the rls-hardening follow-ups (hall donations without debit, etc.).
2. **ADM-02** Email confirmation with the new email. Account security and recovery. Needs an auth-flow change because Confirm email is deliberately off.

Verified 2026-10-15 (Conor playtest on test.restoriaidle.com): **BUG-01** (#304), **BUG-02** (#310, Items `Tradeable` column; not #377), **BUG-04** (#333).

Workflow doc: Cursor cloud agents for commits, pushes, and migrations — **#384**.

### P1: Next

5. **SYS-01** + **QST-02** + **OQ-09** tutorial flow. In Progress (#386, `sys/tutorial-flow`). OQ-09 answered 2026-10-15. Cow fight unchanged. QST-01 closed via #323 and #270.
6. **SOC-01** guild hall tiers. In Progress (`sys/guild-hall-tiers`). **SOC-04** mass bosses remain Ready for Proposal (owner Sys; Eco numbers), queued after the tutorial.
7. **ADM-06** Regenerate the server item data bundle at the next staging deploy so the 4 new potions are in `supabase/functions/_shared/game-database.json`.
8. **ECO-04** Alchemy potion sell prices + Bazaar floors. Merged (#385).
9. **ADM-03** Admin dashboard with event ledger. Visibility into exploits and economy.
10. **SYS-05 + NTF-01/02/03/04/06** Notifications core. Biggest idle-game QoL win.
11. **ADM-04** Report/ideas button → Discord webhook. In Progress / Review (P1 form + submit-feedback).
12. **Decision session on OQ-01..02, OQ-04..07, OQ-11, OQ-15.** OQ-03 answered (84/168); OQ-09 answered (tutorial lock-back). Unblocks MAP-01, ECO-03, ARC-01, WLD-01.
13. **ECO-01** Bazaar total level 200 and **ECO-03** Plaza points. Economy health, after the decisions.
14. **MAP-01** Region map (+ **MAP-04** landing nodes). Foundation for the isles/citadel.
15. **ARC-01** Enchant tablets and **ARC-02** Essence rework (design doc together).
16. **QST-04** Goblin Trouble, **QST-06** Quest recipe rewards, **SKL-04** Cooking multi-output, **ITM-06** Chromium/Vanadium recolor. Content with low dependencies.
17. **UI-05** asset pack, **UI-07** green/gold rules, **ART-01** spec sheet. Unblocks the whole UI/art track.

### P2: After

ARC-03/04/07/08/09 · ITM-01/03/04/05/07 · SKL-01/03/05 · QST-03/05/07/12 ·
MAP-01b/02/03 · SOC-03 · WLD-01 (once decided) · WLD-02 · TTL-00/02/03 ·
UI-01/02/03/04/06/12 · ART-02/04/05/06 · NTF-05/07/08/09 · ADM-05 Telemetry ·
SYS-06 clock.

### Later

DNG-01 Catacombs · SKL-02 Thievery companions · SKL-06
Tides · QST-08 Balrog · UI-14 Language · MEM-01..05 Membership (after OQ-06 and
payments).

### Inbox / Unset (Vari to decide priority)

**ITM-08** Strength potions still give % damage; Eco to propose flat ranges (Awaiting Approval).
**UI-16** Track `docs/item-icon-plan.md` and `docs/flutter-migration.md` (Inbox).
**ADM-07** Branch cleanup report for merged `coord/*` and stale branches (Ops, Inbox, report only).

---

## 5. Category sections

Legend: **Dup** = duplicate/overlap · **Dep** = depends on. Owner names are the
short roster in [AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) (see
[Appendix B](#appendix-b-specialist-bots)). Notes hold **Desc** and **Accept**
(`TBD (owner to propose)` when unknown).

### ADM: Admin / Ops / Security

| ID | Title (Conor's words) | Status | Ready | Pri | Dep | Owner | Next | Notes |
|---|---|---|---|---|---|---|---|---|
| ADM-01 | Check supabase and cloudflare for issues and errors, check for row level security | Ready for Proposal | Ready | **P0** | none | Ops | Re-run Security Advisor; leaked-password protection; review rls follow-ups #2–9, #13–17 | Desc: Audit test and live Supabase/Cloudflare for RLS, logs, and advisor issues. Accept: TBD (owner to propose). Also Worker/edge logs and HTTP 546 CPU kills. |
| ADM-02 | Set up email confirmation with new email | Ready for Proposal | Ready | **P0** | *soft:* ADM-01 | Ops | Spec confirm-email flow on the test project first | Desc: Turn on Confirm email with Restoria SMTP without breaking character creation. Accept: TBD (owner to propose). Confirm email is **OFF on purpose** (`deployment.md`): no session → `profiles` RLS. Needs custom SMTP, confirm-link redirect, and a "check your email" gate. |
| ADM-03 | admin dashboard with event ledger | Inbox | Inbox | P1 | ADM-01, SYS-05 (event log) | Ops | TBD (Ops) | Desc: Admin dashboard with an event ledger, building on dev accounts, reports tables, and guild/bazaar ledgers. Accept: TBD (owner to propose). Blocks ADM-05. |
| ADM-04 | Ingame report/ideas button that links to discord with webhook *(moved from UI)* | Review | In Progress | P1 | ADM-01 | Ops + Ui | Playtest on test after Conor sets the two test function secrets | Desc: In-game report/ideas button that posts to Discord through a webhook. Accept: Settings form (Bug / Suggestion / Player) for signed-in players; 60s cooldown, 5/24h, global 20/min queue; webhook secret `FEEDBACK_DISCORD_WEBHOOK_URL`; tag map `FEEDBACK_DISCORD_TAG_IDS`. No Phase 3 status. Webhook URL must be a server secret; send through an edge function, never from the client. |
| ADM-05 | Telemetry? | Needs Clarification | Blocked on OQ-16 | P2 | OQ-16, ADM-03 | Ops | Vari answers OQ-16 | Desc: Telemetry — what to measure, which vendor, privacy/consent (OQ-16). Accept: TBD (owner to propose). Could start as rows in the server event ledger. |
| ADM-06 | Regenerate the server item data bundle so the 4 new potions are on staging | Ready for Proposal | Ready | P1 | none | Ops | Regenerate the bundle at the next staging deploy | Desc: `supabase/functions/_shared/game-database.json` is built by `tools/bundle_game_edge.sh` and is not committed. Accept: staging `game` function serves the 4 new potions from #377. |
| ADM-07 | Branch cleanup report for merged coord/* and stale branches | Inbox | Inbox | Unset (Vari to decide) | none | Ops | Write a report-only list of merged `coord/*` and stale branches | Desc: Report only — list merged `coord/*` leftovers and stale `cursor/*` branches. Accept: TBD (owner to propose). No deletes until Vari says so. |

### BUG: Bugs and fixes

| ID | Title | Status | Ready | Pri | Dep | Owner | Next | Notes |
|---|---|---|---|---|---|---|---|---|
| BUG-01 | Fennels second step in getting started isn't working properly… | Verified | Playtested | **P0** | none | QA | — | Desc: Getting Started Hold steps regressed when potatoes were cooked. Accept: step-latch holds; Conor playtested on test.restoriaidle.com 2026-10-15. Fixed by #304. All Hold: steps covered; no separate follow-up. See [Appendix A](#appendix-a-fennel-getting-started-bug-analysis). **Dup:** QST-01, QST-02. |
| BUG-02 | Fix selling "untradeable" items to shops. | Verified | Playtested | **P0** | OQ-05 | QA + Eco | — | Desc: Untradeable items must stay off the Bazaar. Accept: Items `Tradeable` column; false for Machete, Excavator's Pickaxe, Stolen Coin Purse, Beggar's Hood; shops unchanged. Fixed by #310 (not #377). Verified 2026-10-15. **Overlap:** QST-12 |
| BUG-03 | Fixes: todo- drops/recipes | Merged | On test-launch | P1 | none | QA | — | Desc: Todo drops/recipes. Accept: closed 2026-10-13; no fixing PR in `git log`; solved before tracking. |
| BUG-04 | Ranked PvP reward exploit | Verified | Playtested | **P0** | none | QA | — | Desc: Ranked PvP reward exploit. Accept: server mints fight ID, picks opponent, pays; cap 5 paid wins/day midnight UTC; idempotent retries. Fixed in #333. Verified 2026-10-15. |

### QST: Quests and dialogue

| ID | Title | Status | Ready | Pri | Dep | Owner | Next | Notes |
|---|---|---|---|---|---|---|---|---|
| QST-01 | Fix dialogue for getting started and green thumb | Merged | On test-launch | P1 | SYS-01, BUG-01 | Writer | — | Desc: Getting Started and Green Thumb dialogue. Accept: closed 2026-10-13 via #323 and #270. **Dup cluster** with BUG-01 / QST-02. |
| QST-02 | Make getting started a mandatory tutorial… 5 actions guaranteed as potatoes, only fennel showing at first, then gather, then combat… | In Progress | In progress | P1 | BUG-01, SYS-01 | Design + Writer | Continue #386 on `sys/tutorial-flow` | Desc: Mandatory Getting Started tutorial. Accept: decisions log 2026-10-15 (lock-back, guarantees, Cow step, farewell). Cow fight is unchanged. OQ-09 answered. In Progress with SYS-01 on #386 / `sys/tutorial-flow`. |
| QST-03 | Asking king about the queen and he describes a dragon but doesn't say it outright | Inbox | Inbox | P2 | SYS-01 | Writer | TBD (Writer) | Desc: King describes a dragon when asked about the queen, without saying it outright. Accept: TBD (owner to propose). Ties to branch `castle-crypt-dragon`. |
| QST-04 | Goblin Trouble (early)… Fight scouts at the Goblin Camp, then the Chief… riverside chest as thievery mark… | Inbox | Inbox | P1 | none (Goblin Camp exists) | Writer + Design | TBD (Writer) | Desc: Early combat quest — Goblin Camp scouts, then the Chief, riverside chest as a thievery mark. Accept: TBD (owner to propose). "First real combat quest" after QST-02. |
| QST-05 | Giants on the Ridge (late)… wyvern… giant-bone craft unlock | Inbox | Inbox | P2 | QST-06 | Writer + Design | TBD (Writer) | Desc: Late quest at the existing Giant Camp — wyvern and giant-bone craft unlock. Accept: TBD (owner to propose). |
| QST-06 | Quests can give crafting recipes for the unique items… or just give the items directly | Inbox | Inbox | P1 | none | Design | TBD (Design) | Desc: Quests grant unique-item recipes or the items themselves. Accept: TBD (owner to propose). `RewardRecipe:` parser already exists (`objectives.dart`). |
| QST-07 | Thievery quest that requires lockpicking a locked door, need multiple success to complete step | Inbox | Inbox | P2 | SKL-01 | Writer | TBD (Writer) | Desc: Thievery quest: lockpick a locked door; multiple successes to finish the step. Accept: TBD (owner to propose). **Overlap:** SKL-01..04. |
| QST-08 | 'Balrog' in abandoned mine | Inbox | Inbox | Later | QST-05-style boss tech | Design | TBD (Design) | Desc: Balrog boss in the existing Abandoned Mineshaft (Going Deeper). Accept: TBD (owner to propose). |
| QST-12 | Untradeable/quest item retrieval npc | Needs Clarification | Blocked on OQ-05 | P2 | OQ-05, BUG-02 | Design | TBD (Design) | Desc: NPC who retrieves untradeable/quest items. Accept: TBD (owner to propose). Pair with BUG-02. |
| QST-13 | Barracks Guard says only "Hmph." after Lowly Beggar | Merged | On test-launch | P2 | #369 | Writer | — | Desc: Barracks Guard says only "Hmph." after Lowly Beggar. Accept: `QDL-0031` / `When: completed`; panel keeps the finished quest (#369, also #364). |

### SYS: Core systems

| ID | Title | Status | Ready | Pri | Dep | Owner | Next | Notes |
|---|---|---|---|---|---|---|---|---|
| SYS-01 | Create a dedicated dialogue system *(from UI)* | In Progress | In progress | P1 | none | Systems | Continue #386 on `sys/tutorial-flow` | Desc: Extend the Citadel Guide dialogue MVP to every NPC and quest. Accept: TBD (owner to propose) for the full extension. Tutorial-flow slice In Progress with QST-02 / OQ-09 on #386 / `sys/tutorial-flow`. Specs: `docs/specs/SYS-01-dialogue.md`, `docs/specs/SYS-01_dialogue_screen.md`. QST-01 done (#323/#270). Still blocks QST-03. |
| SYS-02 | Should there be a mechanic for moving between locations… | Verified | Decided | Unset (Vari to decide) | OQ-01 | Design | — | Desc: Travel is a mechanic vs instant. Accept: instant except the necessary delays (OQ-01, 2026-10-13). Unused travel-time setting removed in #336 (SYS-07). |
| SYS-03 | Maximum inventory size? | Merged | On test-launch | Unset (Vari to decide) | none | Design + Eco | — | Desc: Inventory / bank cap. Accept: 84 bag slots / 168 bank slots (#332, 2026-10-13). Blocks UI-12, MEM-01. |
| SYS-04 | Should there be defense or just health? | Needs Clarification | Blocked on OQ-04 | Unset (Vari to decide) | OQ-04 | Design + Eco | Vari answers OQ-04 | Desc: Defense vs health only. DR already shipped in #289; OQ-04 asks whether to keep DR as the defense stat. Accept: TBD (owner to propose). |
| SYS-05 | Notifications system (plumbing for NTF-\*) | Ready for Proposal | Ready | P1 | none | Community | Propose SYS-05 plumbing | Desc: Shared notifications plumbing for NTF-*. Accept: TBD (owner to propose). Today only chat bubbles exist (`notification_bubble.dart`). Blocks NTF-01..09, ADM-03. |
| SYS-06 | Server time clock… weather art or item *(from UI)* | Inbox | Inbox | P2 | none | Systems + Art | TBD (Systems) | Desc: Server time clock, possibly with weather art or an item. Accept: TBD (owner to propose). Overlaps SKL-06 (tides) and UTC-hour leaderboard resets. |
| SYS-07 | Remove the unused travel-time setting | Merged | On test-launch | P2 | none | Systems | — | Desc: Remove the unused travel-time setting. Accept: travel stays instant; no player-facing change. Shipped in #336. |

### ARC: Arcana / Enchanting / Essence / Spells

| ID | Title | Status | Ready | Pri | Dep | Owner | Next | Notes |
|---|---|---|---|---|---|---|---|---|
| ARC-01 | Change enchantments to create tablets… tradeable… "Enchant Items" activity… any arcana level after wizard studies… no arcana exp | Needs Clarification | Blocked on OQ-14 | P1 | OQ-14, BUG-02 | Design + Eco | Vari answers OQ-14 | Desc: Enchantments become tradeable tablets via an "Enchant Items" activity; any Arcana level after wizard studies; no Arcana XP. Accept: TBD (owner to propose). Enchanting Tablet item already exists. Blocks ARC-07, ARC-08. |
| ARC-02 | Rework Essence gathering (maybe it's a raw resource and can also be found naturally while playing?) | Inbox | Inbox | P1 | none | Design + Eco | TBD (Design) | Desc: Rework Essence gathering, maybe as a raw resource found while playing. Accept: TBD (owner to propose). **Dup cluster** with ARC-03, ARC-04. |
| ARC-03 | Make spells require essence to charge… crafting level×5 essence… 10% spell xp on recharge… 1/150 chance to lose a charge | Needs Clarification | Blocked on OQ-13 | P2 | ARC-02, OQ-13 | Design + Eco | Vari answers OQ-13 | Desc: Spells charge with essence (crafting level×5), 10% spell XP on recharge, 1/150 chance to lose a charge. Accept: TBD (owner to propose). Needs essence supply and a Game Bible update. |
| ARC-04 | Add an item that allows for essence to be gathered from any activity with a tertiary chance of 0.1% | Inbox | Inbox | P2 | ARC-02 | Design | TBD (Design) | Desc: Item that gathers essence from any activity at 0.1% tertiary chance. Accept: TBD (owner to propose). Might be *how* ARC-02 is done. |
| ARC-07 | Piercing enchantment that bypasses dr | Needs Clarification | Blocked on OQ-04 | P2 | ARC-01, OQ-04 | Design + Eco | TBD (Design) | Desc: Piercing enchantment that bypasses DR, built as a tablet. Accept: TBD (owner to propose). |
| ARC-08 | Shield enchantment that adds a block chance, reducing incoming damage to half. | Needs Clarification | Blocked on OQ-04 | P2 | ARC-01, OQ-04 | Design + Eco | TBD (Design) | Desc: Shield enchantment with a block chance that halves incoming damage, built as a tablet. Accept: TBD (owner to propose). |
| ARC-09 | Maybe perk or item to make potions last for more actions | Inbox | Inbox | P2 | none | Design | TBD (Design) | Desc: Perk or item so potions last for more actions. Accept: TBD (owner to propose). Overlaps ITM-05. |

### ITM: Items and gear

| ID | Title | Status | Ready | Pri | Dep | Owner | Next | Notes |
|---|---|---|---|---|---|---|---|---|
| ITM-01 | New items: blessings, can be for specific skills, back slot item | Needs Clarification | Blocked on OQ-12 | P2 | OQ-12, WLD-01 | Design | TBD (Design) | Desc: Skill-specific blessings as a back-slot item. Accept: TBD (owner to propose). Name clash: Temple "Be blessed" overheal amenity already exists. |
| ITM-03 | Add archer armor. Archers quiver, leather bracers, tunic | Needs Clarification | Blocked on OQ-02 | P2 | OQ-02 | Design + Art | TBD (Design) | Desc: Archer armor — archers quiver, leather bracers, tunic. Accept: TBD (owner to propose). **Dup cluster** with ITM-04 and OQ-02. |
| ITM-04 | Hunters quiver, direct upgrade to base quiver | Needs Clarification | Blocked on OQ-02 | P2 | OQ-02, OQ-12 | Design | TBD (Design) | Desc: Hunter's quiver, a direct upgrade to the base quiver. Accept: TBD (owner to propose). Unclear whether "Archers quiver" (ITM-03) is the same item. |
| ITM-05 | Add more potions for skill bonuses | Inbox | Inbox | P2 | none | Design + Eco | TBD (Design) | Desc: Add more potions for skill bonuses. Accept: TBD (owner to propose). Overlaps ARC-09. |
| ITM-06 | Make chromium red and vanadium green, swap already used images and recolor existing ones. | Ready for Proposal | Ready | P1 | none | Art | Propose the recolor swap | Desc: Chromium red, vanadium green; swap already-used images and recolor existing ones. Accept: TBD (owner to propose). Precedent: `swap-titanium-tungsten`. |
| ITM-07 | Add Items that increase lockpick chance | Inbox | Inbox | P2 | SKL-01 | Design | TBD (Design) | Desc: Items that increase lockpick chance. Accept: TBD (owner to propose). Thievery cluster. |
| ITM-08 | Strength potions still give % damage; Eco to propose flat ranges | Awaiting Approval | Awaiting Vari | Unset (Vari to decide) | none | Eco | Eco proposes flat damage ranges | Desc: Strength potions still give % damage. Eco proposes flat ranges. Accept: TBD (owner to propose). No ranges written here until Eco's proposal. |

### SKL: Skills and activities

| ID | Title | Status | Ready | Pri | Dep | Owner | Next | Notes |
|---|---|---|---|---|---|---|---|---|
| SKL-01 | Add Recipe items unique to thievery, loot bags/boxes | Inbox | Inbox | P2 | none | Design + Eco | TBD (Design) | Desc: Thievery-only recipe items and loot bags/boxes. Accept: TBD (owner to propose). **Thievery cluster:** SKL-01/02, ITM-07, QST-07, MAP-03. |
| SKL-02 | Higher able thievery companions that can carry out heists for you | Inbox | Inbox | Later | SKL-01 | Design | TBD (Design) | Desc: Higher-tier thievery companions that run heists. Accept: TBD (owner to propose). Companion system is new infrastructure. |
| SKL-03 | Reduce base success chance further at higher levels | Inbox | Inbox | P2 | none | Eco | TBD (Eco) | Desc: Reduce base success chance further at higher levels. Accept: TBD (owner to propose). Unclear which skills: thievery only, or all success-chance skills? |
| SKL-04 | Cooking crafts = more than one food | Ready for Proposal | Ready | P1 | none | Eco | Propose multi-output cooking | Desc: Cooking crafts produce more than one food. Accept: TBD (owner to propose). Small and helps early food supply. |
| SKL-05 | Add fruit trees | Inbox | Inbox | P2 | none | Design | TBD (Design) | Desc: Add fruit trees. Accept: TBD (owner to propose). Botany/woodcutting overlap. |
| SKL-06 | Tides that effect fishing | Inbox | Inbox | Later | SYS-06 | Design | TBD (Design) | Desc: Tides that affect fishing. Accept: TBD (owner to propose). Uses the server clock. |

### ECO: Economy and rewards

| ID | Title | Status | Ready | Pri | Dep | Owner | Next | Notes |
|---|---|---|---|---|---|---|---|---|
| ECO-01 | Require total level 200 to use the bazaar | Needs Clarification | Blocked on OQ-10 | P1 | OQ-10 | Eco | Vari answers OQ-10 | Desc: Bazaar locked until total level 200. Accept: TBD (owner to propose). Anti-bot/alt measure. **Coupled** with MEM-02. |
| ECO-03 | Replace bounty and pvp gold reward with new currency, plaza points… plaza shop for items and exp | Needs Clarification | Blocked on OQ-15 | P1 | OQ-15, Game Bible update | Eco | Vari answers OQ-15 | Desc: Replace bounty and PvP gold with plaza points and a plaza shop. Accept: TBD (owner to propose). **Blocks** SOC-03 leaderboard payouts (soft). Needs a Game Bible update. |
| ECO-04 | Alchemy potion sell prices + Bazaar floors | Merged | On test-launch | P1 | none | Eco | — | Desc: Alchemy potion sell prices and Bazaar floors. Accept: Poison 24→8, Masterwork 2000→2300; NPC sell values are floors. Merged #385. |

### SOC: Social / Competitive

| ID | Title | Status | Ready | Pri | Dep | Owner | Next | Notes |
|---|---|---|---|---|---|---|---|---|
| SOC-01 | 5 guild hall tiers (bank, boxing ring, indoor garden, arcana station, monster cage) | In Progress | In progress | P1 | rls-hardening #3–6 (server hall settlement, withdrawals, rank perms) | Sys; Eco numbers | Continue `sys/guild-hall-tiers` | Desc: Five guild hall tiers — bank, boxing ring, indoor garden, arcana station, monster cage. Accept: each tier is a week of solo gathering (~40,320 items, Eco Reading B costs); one running gold total replacing the 1M hall debt; unlocks at 10k, 40k, 130k, 400k, 1M once materials are in (2026-10-15). Existing shipped tiers: Build the Hall, Counting Room, Boxing Ring. In Progress on `sys/guild-hall-tiers`. |
| SOC-03 | Revolving leaderboards for guilds and pvp… monthly reset… temporary title | Inbox | Inbox | P2 | *soft:* ECO-03, TTL system | Community + Eco | TBD (Community) | Desc: Revolving guild and PvP leaderboards with a monthly reset and a temporary title. Accept: TBD (owner to propose). Leaderboards already exist and are written from the hosted save. |
| SOC-04 | Make bosses solo or mass… scaled by players… contribution drops… lobby queue | Ready for Proposal | Ready | P1 | OQ-08, realtime infra | Sys; Eco numbers | Queued after the tutorial | Desc: Solo or mass bosses, scaled by players, contribution drops, lobby queue. Accept: TBD (owner to propose). Large: new server lobby system. OQ-08 still open. |

### MAP: World and maps

| ID | Title | Status | Ready | Pri | Dep | Owner | Next | Notes |
|---|---|---|---|---|---|---|---|---|
| MAP-01 | Add a region map. continent map, with regions… | Needs Clarification | Blocked on OQ-11 | P1 | OQ-01, OQ-11 | Design + Ui | TBD (Design) | Desc: Continent region map. Accept: TBD (owner to propose). **Foundation:** blocks MAP-01b/02/03. Travel stays instant (no region-gate timers). |
| MAP-01b | Regions can be unlocked at 200, 400, 800 total level citadel can be in the middle with a persistent travel button on every map *(from UI)* | Needs Clarification | Blocked on OQ-11 | P1 | MAP-01, OQ-11 | Design | TBD (Design) | Desc: Region unlocks at 200/400/800 total level; citadel in the middle with a persistent travel button. Accept: thresholds 200/400/800 confirmed (OQ-11); whether quest unlocks also stay is still Open. On hold until map assets. |
| MAP-02 | Start a new map/region, move the depths there, call it the isles… underwater exploration | Inbox | Inbox | P2 | MAP-01 | Design + Art | TBD (Design) | Desc: New region "the isles"; move The Depths (MAP-0009) there; underwater exploration. Accept: TBD (owner to propose). |
| MAP-03 | Move citadel to its own 2nd main map… thievery… low level areas but mostly mid to high | Inbox | Inbox | P2 | MAP-01 | Design | TBD (Design) | Desc: Citadel on its own second main map; thievery; mostly mid-to-high. Accept: TBD (owner to propose). Lore part → WLD-02. |
| MAP-04 | Add proper landing nodes for sub maps | Inbox | Inbox | P1 | none (listed under OQ-01) | Ui | Confirm what shipped on `submap-landing-83f5` | Desc: Proper landing nodes for submaps. Accept: TBD (owner to propose). Branch `submap-landing-83f5` exists; confirm what shipped. |

### WLD: Lore / Races / Religion

| ID | Title | Status | Ready | Pri | Dep | Owner | Next | Notes |
|---|---|---|---|---|---|---|---|---|
| WLD-01 | Replace races and racial bonus with religious alignments… Vesper can become a religious figure or be replaced by churches/shrines | Needs Clarification | Blocked on OQ-07 | P2 (decision P1) | OQ-07 | Design + Art + Writer | Vari answers OQ-07 | Desc: Replace races and racial bonuses with religious alignments; Vesper becomes a religious figure or is replaced by churches/shrines. Accept: TBD (owner to propose). **Affects:** TTL-03, Vesper/QST-0009, race tables/art, ITM-01, ART-06. |
| WLD-02 | Restoria = old crumbling empire, Citadel = nearby empire (lore) | Inbox | Inbox | P2 | MAP-03 | Writer | TBD (Writer) | Desc: Lore: Restoria is an old crumbling empire; the Citadel is a nearby empire. Accept: TBD (owner to propose). Split out of the UI list. |

### UI: UI / UX

| ID | Title | Status | Ready | Pri | Dep | Owner | Next | Notes |
|---|---|---|---|---|---|---|---|---|
| UI-01 | Add images to skill menus | Inbox | Inbox | P2 | ART-01 (spec) | Ui + Art | TBD (Ui) | Desc: Add images to skill menus. Accept: TBD (owner to propose). Waits on ART-01. |
| UI-02 | Make skill menus better | Inbox | Inbox | P2 | UI-01 | Ui | TBD (Ui) | Desc: Improve skill menus. Accept: TBD (owner to propose). Depends on UI-01. |
| UI-03 | Fancier font for headers | Inbox | Inbox | P2 | UI-06 | Ui | TBD (Ui) | Desc: Fancier font for headers. Accept: TBD (owner to propose). Depends on UI-06. |
| UI-04 | Use more icons for buttons, x icon to replace close button | Inbox | Inbox | P2 | UI-05 | Ui | TBD (Ui) | Desc: More button icons, including an X to replace Close. Accept: TBD (owner to propose). Depends on UI-05. |
| UI-05 | Look for ui asset pack | Ready for Proposal | Ready | P1 | none | Art + Ui / Asset Pack Team | Research a UI asset pack | Desc: Find a UI asset pack. Accept: TBD (owner to propose). Gates UI-03/04/06. Asset Pack Team owns research and implementation. |
| UI-06 | Reduce gold borders | Inbox | Inbox | P2 | UI-07 | Ui | TBD (Ui) | Desc: Reduce gold borders. Accept: TBD (owner to propose). Depends on UI-07. |
| UI-07 | Choose rules for use of green and gold in ui | Needs Clarification | Needs Vari | P1 | none (Vari decision) | Ui | Vari chooses green/gold rules | Desc: Formalize when to use green and gold in the UI. Accept: TBD (owner to propose). `Master_Prompt.md` §6 says "gold highlights, soft green accents". |
| UI-12 | Bank and inventory tabs for custom organization | Needs Clarification | Blocked on MEM-01 | P2 | OQ-03, MEM-01 | Ui | TBD (Ui) | Desc: Bank and inventory tabs for custom organization. Accept: TBD (owner to propose). OQ-03 answered (84/168). |
| UI-14 | Language support | Needs Clarification | Blocked on OQ-18 | Later | OQ-18 | Ui | Vari answers OQ-18 | Desc: Language support. Accept: TBD (owner to propose). Copy lives in the DB plus hardcoded Dart strings. |
| UI-15 | Bribe confirmation popup | Review | In review | P1 | none | Ui | Confirm the shipping PR (number unknown) | Desc: Confirm before paying a quest bribe. Accept: TBD (owner to propose). Network nits from #358 (`code`/`noRoom` through `CloudSyncResult` / `HostedCommandReceipt`). **PR number is unknown.** |
| UI-16 | Track docs/item-icon-plan.md and docs/flutter-migration.md | Inbox | Inbox | Unset (Vari to decide) | none | Ui + Sys | TBD (Ui) | Desc: Track existing docs that had no backlog row: `docs/item-icon-plan.md` (unique 32×32 item icons) and `docs/flutter-migration.md` (Flutter/Dart client layout). Accept: TBD (owner to propose). |

### ART: Art direction and animation

| ID | Title | Status | Ready | Pri | Dep | Owner | Next | Notes |
|---|---|---|---|---|---|---|---|---|
| ART-01 | Art spec sheet: simple backgrounds with a player/action spot; sky 360×360, terrain 360×180, foreground 360×60, player/action 64×96 / 96×64 / 96×96, items/critters 24×24, portraits 64×64, enemies/actions 128×160 | Ready for Proposal | Ready | P1 | none | Art | Write the spec into the Game Bible art section | Desc: Art spec sheet with the sizes already listed in the title. Accept: TBD (owner to propose). Agents follow the Game Bible art section. Blocks ART-02/04/05, UI-01. |
| ART-02 | The player has simple jumpy animations and throws its weapon or tool to attack; enemies simpler, maybe no outlines | Inbox | Inbox | P2 | ART-01, ART-04 | Art | TBD (Art) | Desc: Simple jumpy player animations; throw weapon/tool to attack; enemies simpler, maybe no outlines. Accept: TBD (owner to propose). |
| ART-04 | Setup animations using flame | Inbox | Inbox | P2 | ART-01 | Systems + Art | TBD (Art) | Desc: Set up animations using Flame. Accept: TBD (owner to propose). Depends on ART-01. |
| ART-05 | Instead of 4 tabs on the header, make the log have 4 panels with art the name and the total completion… item collection, monster killing, and more sections | Inbox | Inbox | P2 | ART-01 | Ui + Art | TBD (Ui) | Desc: Replace the 4 header tabs with a 4-panel log (art, name, total completion) covering item collection, monster killing, and more. Accept: TBD (owner to propose). |
| ART-06 | Simpler character art (skin tone only) | Needs Clarification | Blocked on WLD-01 | P2 | WLD-01 | Art | TBD (Art) | Desc: Simpler character art (skin tone only). Accept: TBD (owner to propose). Follows from the religion decision. |

### TTL: Titles

| ID | Title | Status | Ready | Pri | Dep | Owner | Next | Notes |
|---|---|---|---|---|---|---|---|---|
| TTL-00 | Title system: prefix vs suffix display | Inbox | Inbox | P2 | none | Writer (copy) + Design | TBD (Writer) | Desc: Title system — prefix vs suffix display. Accept: TBD (owner to propose). Today titles are Wardrobe cosmetics (`ITEM-0301`). |
| TTL-01 | the Undying, suffix, lost after first death | Verified | Exists | Unset (Vari to decide) | TTL-00 | Writer (copy) | Confirm suffix display | Desc: "the Undying" suffix, lost after first death. Accept: item exists (`ITEM-0301`). Only the suffix display may be missing. |
| TTL-02 | the Slayer, suffix, 500,000 monster kills | Inbox | Inbox | P2 | TTL-00 | Writer (copy) + Design | TBD (Writer) | Desc: "the Slayer" suffix at 500,000 monster kills. Accept: TBD (owner to propose). Kill statistics exist. |
| TTL-03 | Pureblooded, prefix, lost after first race change | Needs Clarification | Blocked on OQ-07 | P2 | **OQ-07** | Writer (copy) + Design | Vari answers OQ-07 | Desc: Pureblooded prefix, lost after first race change. Accept: TBD (owner to propose). Meaningless if races are removed. |

### MEM: Membership QoL

All MEM items need payments infra and a Game Bible change (`Master_Prompt.md`
bans monetization unless it's in the sources). Econ owns the fairness review.

| ID | Title | Status | Ready | Pri | Dep | Owner | Next | Notes |
|---|---|---|---|---|---|---|---|---|
| MEM-01 | Bank space | Needs Clarification | Blocked on OQ-06 | Later | OQ-06, OQ-03 | Eco | TBD (Eco) | Desc: Membership bank space. Accept: TBD (owner to propose). OQ-03 answered (84/168). Needs payments infra and a Game Bible change. |
| MEM-02 | Instant access to the bazaar at total level 1 | Needs Clarification | Blocked on OQ-06 | Later | OQ-06, ECO-01 | Eco | TBD (Eco) | Desc: Members get Bazaar access at total level 1. Accept: TBD (owner to propose). **Fairness flag:** lets a paying alt skip the anti-bot gate. |
| MEM-03 | Pick your name color | Needs Clarification | Blocked on OQ-06 | Later | OQ-06 | Eco | TBD (Eco) | Desc: Membership name color. Accept: TBD (owner to propose). Name color already exists for free; would it be taken away? |
| MEM-04 | Double afk time | Needs Clarification | Blocked on OQ-06 | Later | OQ-06 | Eco | TBD (Eco) | Desc: Double AFK time (24h → 48h). Accept: TBD (owner to propose). Edge CPU replay cost, see `fafa140e`. |
| MEM-05 | 2 extra bazaar slots (4 free) | Needs Clarification | Blocked on OQ-06 | Later | OQ-06 | Eco | TBD (Eco) | Desc: Two extra Bazaar slots (wording said 4 free). Accept: TBD (owner to propose). Today **6** free slots; "4 free" would cut what players have now. |

### NTF: Notifications

All depend on SYS-05. Owner: **Notifs**.

| ID | Event | Status | Ready | Pri | Dep | Owner | Next | Notes |
|---|---|---|---|---|---|---|---|---|
| NTF-01 | Activity stopped after afk | Inbox | Inbox | P1 | SYS-05 | Notifs | TBD (Notifs) | Desc: Notify when an activity stops after AFK. Accept: TBD (owner to propose). |
| NTF-02 | Inventory full | Needs Clarification | Blocked on SYS-05 | P1 | SYS-05, OQ-03 | Notifs | TBD (Notifs) | Desc: Notify when inventory is full. Accept: TBD (owner to propose). OQ-03 answered (84/168). |
| NTF-03 | Food depleted | Inbox | Inbox | P1 | SYS-05 | Notifs | TBD (Notifs) | Desc: Notify when food is depleted. Accept: TBD (owner to propose). |
| NTF-04 | Production queue finished | Inbox | Inbox | P1 | SYS-05 | Notifs | TBD (Notifs) | Desc: Notify when a production queue finishes. Accept: TBD (owner to propose). |
| NTF-05 | Crop ready | Inbox | Inbox | P2 | SYS-05 | Notifs | TBD (Notifs) | Desc: Notify when a crop is ready. Accept: TBD (owner to propose). |
| NTF-06 | Quest step completed | Inbox | Inbox | P1 | SYS-05, BUG-01 | Notifs | TBD (Notifs) | Desc: Notify when a quest step completes. Accept: TBD (owner to propose). Needs persisted steps or it fires again and again. BUG-01 latch is Verified. |
| NTF-07 | Guild invitation | Inbox | Inbox | P2 | SYS-05 | Notifs | TBD (Notifs) | Desc: Notify on a guild invitation. Accept: TBD (owner to propose). |
| NTF-08 | Direct message | Inbox | Inbox | P2 | SYS-05 | Notifs | TBD (Notifs) | Desc: Notify on a direct message. Accept: TBD (owner to propose). Already partly done via chat bubbles. |
| NTF-09 | Someone bought your Bazaar listing | Inbox | Inbox | P2 | SYS-05 | Notifs | TBD (Notifs) | Desc: Notify when someone buys your Bazaar listing. Accept: TBD (owner to propose). |

### DNG: Dungeons

| ID | Title | Status | Ready | Pri | Dep | Owner | Next | Notes |
|---|---|---|---|---|---|---|---|---|
| DNG-01 | "The catacombs"… waves of skeletons and zombies… gathering actions… monsters get harder… solo survival / group dungeons with roles / secondary timer | Needs Clarification | Blocked on OQ-17 | Later | OQ-17, SOC-04 (group tech), SYS-05 | Design | Vari answers OQ-17 | Desc: Catacombs — waves of skeletons and zombies, gathering actions, monsters get harder; solo survival and/or group roles / secondary timer. Accept: TBD (owner to propose). |

### 5.1 Duplicates and overlaps

| Cluster | Items | Agreed handling |
|---|---|---|
| Citadel as region | UI "Citadel can be its own region…", UI "citadel can be in the middle…", MAP-03 | One item, MAP-03. Lore → WLD-02, travel button → MAP-01b |
| Region unlock vs region map | MAP-01b (200/400/800) vs MAP-01 | MAP-01 builds the map, MAP-01b sets the unlock rule. OQ-11: thresholds 200/400/800 confirmed; quest-unlock overlap still Open; on hold for map assets. |
| Getting Started | BUG-01 Fennel bug, QST-01 dialogue fix, QST-02 mandatory tutorial | QST-01 Merged (#323, #270). BUG-01 Verified (#304). QST-02 / OQ-09 / SYS-01 In Progress (#386, `sys/tutorial-flow`). Cow fight unchanged. |
| Essence | ARC-02 rework, ARC-04 0.1% essence item, ARC-03 spell charging | One "Essence economy" design doc |
| Enchanting | ARC-01 tablets, ARC-07 piercing, ARC-08 shield | Tablets first, then new enchants ship as tablets |
| Thievery | SKL-01 loot bags/recipes, SKL-02 companions, ITM-07 lockpick items, QST-07 lockpick quest, MAP-03 citadel thievery | One "Thievery expansion" epic |
| Archery | ITM-03 archer armor + archers quiver, ITM-04 hunters quiver, OQ-02 arrows | Settle OQ-02 first. Check whether "archers quiver" and "hunters quiver" are the same item. |
| Back slot | ITM-01 blessings (back), Quiver, ITM-04 | OQ-12 |
| Untradeable | BUG-02, QST-12 retrieval NPC, ARC-01 tradeable tablets | OQ-05 defines the rule for all three |
| Clock | SYS-06 server time, SKL-06 tides, SOC-03 monthly resets | One shared server clock |
| Titles vs religion | TTL-03 Pureblooded, WLD-01 | OQ-07 |
| Bazaar access | ECO-01 (level 200), MEM-02 (level 1 for members), MEM-05 (slots) | Decide together |
| Report button | UI list vs admin | ADM-04 |

### 5.2 Key dependencies

```
OQ-01/OQ-11 ─► MAP-01 region map ─► MAP-01b unlocks ─► MAP-02 isles, MAP-03 citadel map
SYS-01 dialogue system ─► QST-01 dialogue fixes (Merged #323/#270), QST-02 tutorial (In Progress #386 / `sys/tutorial-flow` with OQ-09), QST-03 king/queen
BUG-01 (persist steps; Verified #304, Conor playtest 2026-10-15) ─► QST-02 tutorial, NTF-06 quest-step notifications
QST-02 tutorial ─► SOC-04 mass bosses (Ready for Proposal after tutorial). SOC-01 guild hall In Progress on `sys/guild-hall-tiers`
OQ-15 + Bible ─► ECO-03 plaza points ─► bounty/pvp reward swap, SOC-03 leaderboard payouts
SYS-05 notifications ─► NTF-01..09
ARC-01 tablets ─► ARC-07 piercing, ARC-08 shield
ARC-02 essence rework ─► ARC-03 spell charges, ARC-04 essence item
OQ-07 religion ─► WLD-01 ─► TTL-03 Pureblooded, Vesper/QST-0009, ITM-01 blessings, ART-06
OQ-03 inventory size (answered: 84 bag / 168 bank, #332) ─► UI-12 tabs, MEM-01 bank space, NTF-02
OQ-05 untradeable ─► BUG-02, QST-12, ARC-01
ADM-01 audit ─► ADM-02 email, ADM-03 dashboard ─► ADM-05 telemetry
rls-hardening #3–6 (server hall settlement) ─► SOC-01 guild hall tiers
UI-07 color rules + UI-05 asset pack ─► UI-03/04/06
ART-01 spec ─► ART-02/04/05, UI-01
```

---

## 6. Done archive

Moved here with PR and date once on `test-launch` (Conor, 2026-10-13: the Done
list tracks test-launch; `main` is updated later). Seeded with work that was
already done when the backlog was approved.

| What | PR / evidence | Date |
|---|---|---|
| Make restoria email | Conor checked it | ≤ 2026-10-12 |
| Make subdomain test server | test.restoriaidle.com → Worker `restoria-idlerpg-staging`, tester passkey gate (`docs/deployment.md`) | ≤ 2026-10-12 |
| Agent workflow docs | PR #299 | ≤ 2026-10-12 |
| Server-authoritative saves (Wave G phase 2 + 4) | `docs/server-authority.md` | ≤ 2026-10-12 |
| RLS hardening migration 026 + advisor social hardening | PR #294, #295; `docs/rls-hardening.md` (19-item follow-up list, partly done; rest tracked in ADM-01) | ≤ 2026-10-12 |
| Dialogue engine MVP (Citadel Guide dialogue, `completedDialogueIds`, save v61) | commit `dd43c020`, `packages/ik_rules/lib/src/dialogue/engine.dart`, DB tables `Dialogues/DialogueNodes/DialogueChoices` (extension tracked in SYS-01) | ≤ 2026-10-12 |
| "the Undying" title (lost after first death) | `ITEM-0301` cosmetic title (suffix display tracked in TTL-01) | ≤ 2026-10-12 |
| Name color (for everyone) | branches `name-color-stone-ink`, `vari-motto-name-color` | ≤ 2026-10-12 |
| Player reports and ignore are hosted | commit `c8428b84` | ≤ 2026-10-12 |
| Developer commands for Vari (proto-admin) | `20261009060000_developer_accounts.sql` | ≤ 2026-10-12 |
| Guild hall tiers 1–3: Build the Hall, Counting Room, Boxing Ring | `packages/ik_rules/lib/src/guild/hall.dart` | ≤ 2026-10-12 |
| Bazaar: 6 offer slots, 1% tax over 100g | `docs/bazaar-api.md`, `market.dart` | ≤ 2026-10-12 |
| Enchanted gear sells at Wizard's Shop (2×) and general merchants (1×), not at the Bazaar | PR #301 (on test-launch; PR #302 promotes to main) | 2026-10-12 |
| SYS-01: show the quest reward popup when a dialogue choice completes a quest | PR #325 (on test-launch) | 2026-10-13 |
| test(parity): walk Getting Started step-latch through Fennel dialogue | PR #327 (on test-launch) | 2026-10-13 |
| test(npc): drive Turn in through the real default commit path | PR #328 (on test-launch) | 2026-10-13 |
| SYS-02b: HandIn latch, farm timer spot, abandon prune | PR #329 (on test-launch) | 2026-10-13 |
| Keep map node labels inside the view on narrow phones | PR #330 (on test-launch) | 2026-10-13 |
| test(unattended): test-only step cap so the catch-up self-heal test runs fast | PR #331 (on test-launch) | 2026-10-13 |
| SYS-03: 84 bag slots / 168 bank slots, leftover loot | PR #332 (on test-launch) | 2026-10-13 |
| SYS-07: unused travel-time setting removed | PR #336 (on test-launch) | 2026-10-13 |
| BUG-04: server-authoritative ranked PvP and bounty payouts | PR #333 (on test-launch); Verified by Conor playtest on test.restoriaidle.com 2026-10-15 | 2026-10-13 |
| QST-01 Getting Started / Green Thumb dialogue | PR #323, #270 (on test-launch) | 2026-10-13 |
| BUG-03 todo drops/recipes | solved before tracking (no fixing PR in `git log`) | 2026-10-13 |
| BUG-01: Fennel Getting Started step-latch | PR #304 (on test-launch); Verified by Conor playtest on test.restoriaidle.com 2026-10-15 | 2026-10-15 |
| BUG-02: Items Tradeable column (untradeable Bazaar block) | PR #310 (on test-launch; not #377); Verified by Conor playtest on test.restoriaidle.com 2026-10-15 | 2026-10-15 |
| Game Bible Regular Bow lines removed | PR #383 (on test-launch) | 2026-10-15 |
| Workflow doc: Cursor cloud agents for commits, pushes, and migrations | PR #384 (on test-launch) | 2026-10-15 |
| Alchemy rework: 4 herb+water potions, water at alchemy stations, drop and price fixes | PR #377 (on test-launch) | 2026-10-15 |
| ECO-04: Alchemy potion sell prices + Bazaar floors | PR #385 (on test-launch) | 2026-10-15 |
| QST-13: Barracks Guard "Hmph." after Lowly Beggar | PR #369 (on test-launch; also #364) | 2026-10-14 |
| docs: backlog tidy and tutorial flow decisions (Oct 15) | PR #387 (on test-launch) | 2026-10-15 |

---

## Appendix A: Fennel "Getting Started" bug analysis

Supports **BUG-01**. Analysis written before #304 (step-latch). That fix is on
test-launch; **Verified** by Conor playtest on test.restoriaidle.com on
2026-10-15. All Hold: steps are covered by the #304 latch; no separate
follow-up.

**Root cause (high confidence):** quest steps aren't saved once they're done.
`getCurrentStepIndex` re-checks every step on every tick, and steps 1–2 of
Getting Started are **live `Hold: Potato x5` checks**. Cooking uses up the raw
potatoes, so the quest drops back to step 1. Today the player needs 5 raw
**and** 5 cooked potatoes at the same time.

### Data (QST-0006, `content/data/game-database.json` → `QuestSteps`)

| Step | ID | Label | Notes |
|---|---|---|---|
| 1 | QSTP-0013 | Gather five potatoes | `Hold: ITEM-0025 x5` |
| 2 | QSTP-0014 | Show Fennel five potatoes | `Hold: ITEM-0025 x5; Talk: NPC-0014` |
| 3 | QSTP-0015 | Cook the potatoes in town | `Visit: LOC-0023; Process: RCP-0001 x5` |
| 4 | QSTP-0016 | Bring Fennel the cooked potatoes | `Hold: ITEM-0058 x5; Talk: NPC-0014` |
| 5 | QSTP-0022 | Hear Fennel's farewell | `Talk: NPC-0014` |

### Code path

- `packages/ik_rules/lib/src/quests/steps.dart:146` `getCurrentStepIndex` loops
  over **every step from the start**, every time, and returns the first step
  `_isStepComplete` says is false. **Nothing records a step as done.** TS twin:
  `src/game/quests/steps.ts:160` (the server reruns the same logic, so the
  hosted save agrees with the client).
- `steps.dart:130` `_isStepComplete` → `objectiveProgressFromStructured`.
- `packages/ik_rules/lib/src/quests/objectives.dart:640-646`: a `Hold` line's
  `current` is **live `inventoryCount(save, itemId)`**, not a counter.
- In contrast, `Process` (`objectives.dart:605`), `Talk`, and `Visit` are stored
  counters/flags (`progress.dart:13 _bumpCounter`, `:67
  applyQuestProcessProgress`, `:334 applyQuestVisitProgress`). These stick.
- `Hold` doesn't consume anything (unlike `Deliver`), so after the step-2 talk
  the player still has 5 raw potatoes. That matches Conor's report.

### Hypothesis

1. The player holds 5 raw potatoes and talks to Fennel. The
   `talk:NPC-0014:QSTP-0014` flag is stored, and the step index moves to 3.
2. They cook potatoes. Each cook bumps `process:RCP-0001` (stored) and
   **removes a raw potato**.
3. Once raw potatoes drop below 5, step 1 (`Hold raw x5`) fails on the next
   check, so `getCurrentStepIndex` returns **0**. The journal shows "Gather five
   potatoes" again, and the step-4 talk is never offered (`questCanTalkToNpc`
   reads the current step).
4. So the quest can only advance while the bag holds **5 raw potatoes and 5
   cooked potatoes at the same time**. Conor's guess is right.
5. Side effect: if the player gathers 5 more raw potatoes, the quest jumps
   straight to step 4. The talk, process, and visit progress all persisted.
   That's the workaround for affected players today.

**Contributing history:** the step-2 "Show Fennel" Hold+Talk step was added in
`eefcbc9d` ("Open NPC Talk as dialogue and show quest step counts"). Getting
Started dates from `6ea1865f`, reworked in #131. No PR from #283–#302 touched
quest step logic. PR #301 touched sell/shops only. So this is long-standing, not
a regression from recent PRs.

**Covered for other quests too:** any quest with a `Hold:` step followed by
steps that use up or move that item had the same problem. The #304 latch
covers all Hold: steps, so there is no separate follow-up.

### Fix directions (Conor chooses)

- **A. Persist step completion:** store a `step:<id>` flag when a step first
  completes. `getCurrentStepIndex` then skips flagged steps. Generic, and fixes
  every quest. Needs a save-shape/parity-fixture update in both Dart and TS.
- **B. Data-only:** change steps 1–2 so they can't regress (e.g. step 1 becomes
  an action/gather counter, or `Hold` only applies while the step is current).
  Smaller, but only fixes this one quest.
- **C. Fold into QST-02 (mandatory tutorial):** redesign the steps with
  guaranteed potato actions.

### Clarifying questions for Conor

1. By "second step", do you mean step 2 *Show Fennel five potatoes* (the
   confirmation talk), with the failure on step 3 *Cook the potatoes*? Did the
   journal jump back to "Gather five potatoes"?
2. Test site or live, and roughly when (PT)? Was it a fresh account?
3. Did you cook all 5 at the Town kitchen (LOC-0023), and did you visit it
   **after** accepting the quest?
4. Should steps lock once done (Fix A, applies to all quests), or do you want
   this fixed only inside the tutorial redesign (QST-02)?
5. Should Fennel **take** the potatoes at step 2 (Deliver) instead of just
   checking them (Hold)?
6. Players stuck right now: is "gather 5 more raw potatoes" an acceptable
   workaround until the fix ships, or do you want a save repair?

---

## Appendix B: Specialist bots

Every bot follows `AGENT_WORKFLOW.md`: plan, then stop for Conor's OK, then PR
into `test-launch`. No bot ever touches `main`. All bots escalate any change to
the Game Bible or DB `Status` to Conor.

| Bot (short name) | Scope | Inputs | Owns sections | Must escalate to Conor |
|---|---|---|---|---|
| **Ops/Security** (Ops) | Supabase (advisors, RLS, logs, migrations test→live), Cloudflare Workers/DNS, edge CPU, secrets hygiene, auth/email, admin dashboard, telemetry | Supabase + Cloudflare connectors (read first), `rls-hardening.md`, `deployment.md`, `server-authority.md` | ADM, rls follow-ups | Any live migration, auth setting change, secret rotation, cost/plan change, data deletion |
| **QA/Bugfix** (QA) | Repro, root cause, parity tests, regression audits (e.g. the `Hold:` audit), playtest checklists | Bug reports, Discord/report button, PRs | BUG | Fix choice when it changes player-facing behavior, save repairs, exploit disclosure |
| **Game Design/Systems** (Sys) | Specs for core systems (dialogue engine, travel, inventory, notifications plumbing, maps, tablets, bosses, dungeons) | Game Bible, DB, backlog | SYS, MAP, ARC (with Eco), DNG, SOC-01/04 | Every open question. Any new system or currency. Changes to Master_Prompt §10 rules. |
| **Content/Quest & Dialogue writer** (Quest) | Quest steps, NPC dialogue, lore, titles copy | Dialogue engine, Game Bible lore | QST, WLD-02, TTL copy | New lore canon (king/queen dragon, religions), reward values |
| **Economy/Balance** (Eco) | Sell values, tradeability, drops, XP, Bazaar gates, plaza points, membership fairness, potions | DB values, Bazaar/leaderboard data | ECO, SKL balance, ITM stats, MEM fairness review | Any currency, membership perk, reward-value change, the "untradeable" definition |
| **UI/UX** (Ui) | Menus, icons, fonts, color rules, tabs, landing nodes, language | Flutter `app_flutter/lib/src/ui`, ART spec | UI, MAP-04, notifications UI | Style rules (green/gold), asset-pack purchase/licence |
| **Art Direction** (Art) | Asset spec, generation/sourcing, recolors, Flame animations | ART spec, Master_Prompt §6 | ART, ITM-06, ART-06 | Style changes, new asset categories, paid assets |
| **Community/Notifications** (Notifs) | Notification events and delivery, Discord webhook, leaderboard seasons, player update mails | SYS-05, Discord, leaderboards | NTF, SOC-03, ADM-04 (with Ops) | Push-permission prompts, season rewards/titles, public announcements |
| **Coordinator** | Backlog and merge order. No code. No design decisions. | `docs/BACKLOG.md`, open PRs into `test-launch` | Backlog hygiene | Any design call, any merge to `test-launch` or `main` |
| **Asset Pack Team** | UI asset pack research and implementation | UI-05, ART spec | UI-05 | Asset-pack purchase/licence |
