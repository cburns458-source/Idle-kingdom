# Restoria master backlog

**Status: Approved by Conor on 2026-10-12.**

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

`Idea` → `Needs decision` → `Ready for plan` → `Planned` (plan approved) →
`In PR` → `On test` → `Live`. Or `Parked` / `Dropped` / `Duplicate of X`.

**Rule:** an item can't move past `Needs decision` while it has an open `OQ-##`.

### 1.3 Priority legend

| Priority | Meaning |
|---|---|
| **P0** | Now: security, exploits, broken onboarding |
| **P1** | Next |
| **P2** | After |
| **Later** | Large or speculative; needs decisions or new infrastructure first |
| — | A question rather than work; resolved through its `OQ-##` |

### 1.4 Fields per item

| Field | Example |
|---|---|
| **ID** | `ARC-01` |
| **Title** (Conor's wording) | "Change enchantments to create tablets…" |
| **Category** | ARC |
| **Status** | see 1.2 |
| **Priority** | P0 / P1 / P2 / Later |
| **Depends on** | IDs (hard) · *soft:* IDs |
| **Blocks** | IDs |
| **Overlaps / duplicates** | IDs |
| **Open questions** | `OQ-##` links |
| **Owner bot** | e.g. Systems bot (see [Appendix B](#appendix-b-specialist-bots)) |
| **Repo touchpoints** | files/tables already involved |
| **Notes / acceptance** | 1–3 lines |
| **Links** | PRs, Discord, playtest notes |

The category tables in section 5 carry the most-used fields as columns; blocks,
overlaps, repo touchpoints and links go in Notes.

### 1.5 Moving items

- When Conor rules on something, add a dated row to the decisions log. Rows are
  immutable once written; a reversal is a new row.
- When an `OQ-##` is answered, record the answer in the decisions log, mark the
  question resolved, and move the items it blocked forward.
- When an item goes `Live`, move it to the done archive with its PR and date.

---

## 2. Decisions log

Conor's rulings, dated. Immutable once written.

| Date | Decision | Evidence |
|---|---|---|
| 2026-10-12 | This backlog (structure, items, IDs, priorities, owner bots) approved | Conor |
| ≤ 2026-10-12 | Workflow: plan → owner OK → PR into `test-launch` → playtest → Conor merges to `main` | `AGENTS.md`, `docs/AGENT_WORKFLOW.md` (PR #299) |
| ≤ 2026-10-12 | Server-authoritative saves: the `game` edge function is the only writer of `player_saves` | `docs/server-authority.md` |
| 2026-10-12 | Enchanted gear sells at Wizard's Shop (2×) and general merchants (1×), not at the Bazaar | PR #301, merged 2026-10-12 08:14 PT (on test-launch; PR #302 promotes to main) |
| ≤ 2026-10-12 | Location art spec: square sources that crop to portrait | `docs/Master_Prompt.md` §6 |
| ≤ 2026-10-12 | Confirm email is OFF on purpose (turning it on breaks character creation) | `docs/deployment.md`; see ADM-02 |

### 2.1 Standing context (facts that shape open items)

- ⚠️ Combat now has HP **and** DR (Damage Resistance): PR #289 "Retune enemy
  base HP and add Damage Resistance". Affects OQ-04.
- ⚠️ Timed travel was removed (branch `remove-timed-travel`). Affects OQ-01.
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

**Guardrail from `Master_Prompt.md` §2:** "Do not add currencies, energy
systems, monetization systems… not defined by the supplied sources." Plaza
points (ECO-03), membership (MEM-\*), and essence-as-charge (ARC-03) each need
Conor to update the Game Bible/DB first, or agents will refuse or stall.

---

## 3. Open questions register

Conor decides. All are open as of 2026-10-12.

### 3.1 Conor's own

| ID | Question | Blocks | Context found | Status |
|---|---|---|---|---|
| OQ-01 | Should moving between locations be a mechanic, or instant? | MAP-01, MAP-04, SYS-02 | Timed travel was removed earlier; travel clocks still exist in hosted code | Open |
| OQ-02 | Should bows require arrows? | ITM-03, ITM-04 | 9 bows, Quiver gives a Hunting XP factor, no arrow items | Open |
| OQ-03 | Maximum inventory size? | SYS-03, UI-12, MEM-01, NTF-02 | No inventory cap key in Config | Open |
| OQ-04 | Defense, or just health? | SYS-04, ARC-07, ARC-08 | DR already shipped in #289, so the question is really "keep DR as the defense stat?" | Open |

### 3.2 Found while building the backlog

| ID | Question | Blocks | Status |
|---|---|---|---|
| OQ-05 | What does "untradeable" mean? Quest items, uniques (Excavator's Pickaxe sells for 69), starter cosmetics (Traveler's Tunic 24), enchanted gear? Should it be an explicit DB column? | BUG-02, QST-12, ARC-01 | Answered 2026-10-12 (Conor): can't be listed on the Bazaar, still sells to shops; untradeable iff its only source is quest rewards; Golden Spud stays tradeable; enchanted Bazaar block unchanged. Items `Tradeable` column. |
| OQ-06 | Membership: price, one-time or subscription, and is it fair? "Instant Bazaar at total level 1" and "double AFK" are close to pay-to-win in a game with a shared market and leaderboards. | MEM-\* | Open |
| OQ-07 | Religion vs races: replace races fully? What happens to existing race bonuses, race starting items, Vesper, "A Change of Skin", and the Pureblooded title? | WLD-01, TTL-03 | Open |
| OQ-08 | Mass bosses: which bosses? What are the scaling and contribution formulas? Are there server-side lobbies (new realtime infra)? | SOC-04 | Open |
| OQ-09 | Mandatory tutorial: what happens to existing players partway through Getting Started, and to players who already finished it? | QST-02 | Open |
| OQ-10 | Bazaar gate at total level 200: what about existing players under 200 who have live offers? | ECO-01 | Open |
| OQ-11 | Region unlocks (200/400/800 total level) vs the existing quest-based unlocks (Through the Thicket, Going Deeper, Forged in Fire). Which wins? | MAP-01, MAP-01b | Open |
| OQ-12 | Back slot conflict: blessings, the Quiver/Hunter's Quiver, and capes all want the Back slot. | ITM-01, ITM-04 | Open |
| OQ-13 | Spell charging: does the 1/150 per-action loss stack with "only spent on relevant actions"? What happens to existing spells? | ARC-03 | Open |
| OQ-14 | Tablet rework migration: what happens to enchanted items players already own, and to recipes they've learned? | ARC-01 | Open |
| OQ-15 | Plaza points: can they be traded? Do bounties keep any gold? What goes in the shop's item and XP catalog? | ECO-03 | Open |
| OQ-16 | Telemetry: what do you want to measure, which vendor, and what privacy/consent rules? | ADM-05 | Open |
| OQ-17 | Catacombs: solo survival, group roles, or both first? | DNG-01 | Open |
| OQ-18 | Language support: which languages, and when? (Copy is in the DB plus hardcoded Dart strings.) | UI-14 | Open |

---

## 4. Now / Next / Later board

Just IDs, in order. Conor re-orders this.

### P0: Now (security, exploits, broken onboarding)

1. **BUG-01** Fennel Getting Started step bug. Every new player hits it in the first 5 minutes.
2. **ADM-01** Supabase/Cloudflare/RLS audit. Re-run advisors, do leaked-password protection, close the rls-hardening follow-ups (hall donations without debit, etc.).
3. **BUG-02** Untradeable selling exploit. Gold/economy integrity. Blocked on OQ-05 (the definition), so get that answer first.
4. **ADM-02** Email confirmation with the new email. Account security and recovery. Needs an auth-flow change because Confirm email is deliberately off.

### P1: Next

5. **SYS-01** Dialogue system (extend the MVP). Unblocks QST-01/02/03.
6. **QST-02 + QST-01** Mandatory tutorial and Getting Started/Green Thumb dialogue. One pass, right after BUG-01.
7. **ADM-03** Admin dashboard with event ledger. Visibility into exploits and economy.
8. **SYS-05 + NTF-01/02/03/04/06** Notifications core. Biggest idle-game QoL win.
9. **ADM-04** Report/ideas button → Discord webhook. Cheap, and feeds QA.
10. **Decision session on OQ-01..07, OQ-11, OQ-15.** Unblocks MAP-01, ECO-03, ARC-01, WLD-01.
11. **ECO-01** Bazaar total level 200 and **ECO-03** Plaza points. Economy health, after the decisions.
12. **MAP-01** Region map (+ **MAP-04** landing nodes). Foundation for the isles/citadel.
13. **ARC-01** Enchant tablets and **ARC-02** Essence rework (design doc together).
14. **QST-04** Goblin Trouble, **QST-06** Quest recipe rewards, **SKL-04** Cooking multi-output, **ITM-06** Chromium/Vanadium recolor. Content with low dependencies.
15. **UI-05** asset pack, **UI-07** green/gold rules, **ART-01** spec sheet. Unblocks the whole UI/art track.

### P2: After

ARC-03/04/07/08/09 · ITM-01/03/04/05/07 · SKL-01/03/05 · QST-03/05/07/12 ·
MAP-01b/02/03 · SOC-01/03 · WLD-01 (once decided) · WLD-02 · TTL-00/02/03 ·
UI-01/02/03/04/06/12 · ART-02/04/05/06 · NTF-05/07/08/09 · ADM-05 Telemetry ·
SYS-06 clock.

### Later

SOC-04 Mass bosses · DNG-01 Catacombs · SKL-02 Thievery companions · SKL-06
Tides · QST-08 Balrog · UI-14 Language · MEM-01..05 Membership (after OQ-06 and
payments).

---

## 5. Category sections

Legend: **Dup** = duplicate/overlap · **Dep** = depends on. Owner names refer to
the bots in [Appendix B](#appendix-b-specialist-bots) (Ops = Ops/Security, QA =
QA/Bugfix, Design = Game Design/Systems, Systems = Game Design/Systems, Writer =
Content/Quest & Dialogue writer, Econ = Economy/Balance, UI = UI/UX, Art = Art
Direction, Community = Community/Notifications).

### ADM: Admin / Ops / Security

| ID | Title (Conor's words) | Status | Pri | Dep | Owner | Notes |
|---|---|---|---|---|---|---|
| ADM-01 | Check supabase and cloudflare for issues and errors, check for row level security | Ready for plan | **P0** | none | Ops | Re-run Security Advisor (rls-hardening #18), turn on leaked-password protection, review the open follow-ups #2–9 and #13–17, Worker/edge logs, HTTP 546 CPU kills |
| ADM-02 | Set up email confirmation with new email | Ready for plan | **P0** | *soft:* ADM-01 | Ops | Confirm email is **OFF on purpose** (`deployment.md`): turning it on breaks character creation (no session → `profiles` RLS). Needs custom SMTP from the Restoria email, a confirm-link redirect, and a "check your email" gate. Test project first. |
| ADM-03 | admin dashboard with event ledger | Idea | P1 | ADM-01, SYS-05 (event log) | Ops | Can build on dev accounts, reports tables, and guild/bazaar ledgers. Blocks ADM-05. |
| ADM-04 | Ingame report/ideas button that links to discord with webhook *(moved from UI)* | Idea | P1 | ADM-01 | Ops + UI | Webhook URL must be a server secret. Send through an edge function, never from the client. |
| ADM-05 | Telemetry? | Needs decision | P2 | OQ-16, ADM-03 | Ops | Could start as rows in the server event ledger |

### BUG: Bugs and fixes

| ID | Title | Status | Pri | Dep | Owner | Notes |
|---|---|---|---|---|---|---|
| BUG-01 | Fennels second step in getting started isn't working properly… | Needs decision (fix direction A/B/C) | **P0** | none | QA | Root cause in [Appendix A](#appendix-a-fennel-getting-started-bug-analysis). **Dup/overlap:** QST-01, QST-02. Blocks QST-02, NTF-06. |
| BUG-02 | Fix selling "untradeable" items to shops. | In PR | **P0** | OQ-05 | QA + Econ | Items `Tradeable` column (default true; false for Machete, Excavator's Pickaxe, Stolen Coin Purse, Beggar's Hood). Bazaar refuses them client and server side; shops unchanged. Migration `20261012170000` cancels open orders. `validateTradeability` keeps quest-only items untradeable. **Overlap:** QST-12 |
| BUG-03 | Fixes: todo- drops/recipes | Needs decision | P1 | Conor's list | QA | Placeholder. Needs Conor's specific drop/recipe list. |

### QST: Quests and dialogue

| ID | Title | Status | Pri | Dep | Owner | Notes |
|---|---|---|---|---|---|---|
| QST-01 | Fix dialogue for getting started and green thumb | Idea | P1 | SYS-01, BUG-01 | Writer | **Dup cluster** with BUG-01 / QST-02. Green Thumb lines were restored in #270. |
| QST-02 | Make getting started a mandatory tutorial… 5 actions guaranteed as potatoes, only fennel showing at first, then gather, then combat… | Needs decision | P1 | BUG-01, SYS-01, OQ-09 | Design + Writer | Redesigning this could replace the buggy Hold steps entirely |
| QST-03 | Asking king about the queen and he describes a dragon but doesn't say it outright | Idea | P2 | SYS-01 | Writer | Ties to castle crypt dragon content (branch `castle-crypt-dragon`) |
| QST-04 | Goblin Trouble (early)… Fight scouts at the Goblin Camp, then the Chief… riverside chest as thievery mark… | Idea | P1 | none (Goblin Camp exists) | Writer + Design | "First real combat quest". Fits the tutorial hand-off from QST-02. |
| QST-05 | Giants on the Ridge (late)… wyvern… giant-bone craft unlock | Idea | P2 | QST-06 | Writer + Design | Giant Camp exists |
| QST-06 | Quests can give crafting recipes for the unique items… or just give the items directly | Idea | P1 | none | Design | `RewardRecipe:` note parser already exists (`objectives.dart`) |
| QST-07 | Thievery quest that requires lockpicking a locked door, need multiple success to complete step | Idea | P2 | SKL-01 | Writer | **Overlap:** thievery cluster (SKL-01..04) |
| QST-08 | 'Balrog' in abandoned mine | Idea | Later | QST-05-style boss tech | Design | Abandoned Mineshaft exists (Going Deeper) |
| QST-12 | Untradeable/quest item retrieval npc | Needs decision | P2 | OQ-05, BUG-02 | Design | Pair with BUG-02 |

### SYS: Core systems

| ID | Title | Status | Pri | Dep | Owner | Notes |
|---|---|---|---|---|---|---|
| SYS-01 | Create a dedicated dialogue system *(from UI)* | Ready for plan | P1 | none | Systems | **MVP already exists** (Citadel Guide). This item = extend it to every NPC and quest. Blocks QST-01/02/03. |
| SYS-02 | Should there be a mechanic for moving between locations… | Needs decision | — | OQ-01 | Design | |
| SYS-03 | Maximum inventory size? | Needs decision | — | OQ-03 | Design + Econ | Blocks UI-12, MEM-01 |
| SYS-04 | Should there be defense or just health? | Needs decision | — | OQ-04 | Design + Econ | |
| SYS-05 | Notifications system (plumbing for NTF-\*) | Ready for plan | P1 | none | Community | Today only chat bubbles exist (`notification_bubble.dart`). Blocks NTF-01..09, ADM-03. |
| SYS-06 | Server time clock… weather art or item *(from UI)* | Idea | P2 | none | Systems + Art | Overlaps SKL-06 (tides) and leaderboard resets (already UTC-hour based) |

### ARC: Arcana / Enchanting / Essence / Spells

| ID | Title | Status | Pri | Dep | Owner | Notes |
|---|---|---|---|---|---|---|
| ARC-01 | Change enchantments to create tablets… tradeable… "Enchant Items" activity… any arcana level after wizard studies… no arcana exp | Needs decision | P1 | OQ-14, BUG-02 | Design + Econ | "Enchanting Tablet" item already exists. Tradeable tablets interact with the Bazaar enchanted-item block. Blocks ARC-07, ARC-08. |
| ARC-02 | Rework Essence gathering (maybe it's a raw resource and can also be found naturally while playing?) | Idea | P1 | none | Design + Econ | **Dup cluster** with ARC-03, ARC-04. Decide these together. |
| ARC-03 | Make spells require essence to charge… crafting level×5 essence… 10% spell xp on recharge… 1/150 chance to lose a charge | Needs decision | P2 | ARC-02, OQ-13 | Design + Econ | Needs essence supply to be sorted first. Needs a Game Bible update (guardrail). |
| ARC-04 | Add an item that allows for essence to be gathered from any activity with a tertiary chance of 0.1% | Idea | P2 | ARC-02 | Design | Might be *how* ARC-02 is done |
| ARC-07 | Piercing enchantment that bypasses dr | Needs decision | P2 | ARC-01, OQ-04 | Design + Econ | Build as a tablet |
| ARC-08 | Shield enchantment that adds a block chance, reducing incoming damage to half. | Needs decision | P2 | ARC-01, OQ-04 | Design + Econ | Build as a tablet |
| ARC-09 | Maybe perk or item to make potions last for more actions | Idea | P2 | none | Design | Overlaps ITM-05 (more potions) |

### ITM: Items and gear

| ID | Title | Status | Pri | Dep | Owner | Notes |
|---|---|---|---|---|---|---|
| ITM-01 | New items: blessings, can be for specific skills, back slot item | Needs decision | P2 | OQ-12, WLD-01 | Design | Name clash: Temple "Be blessed" overheal amenity already exists. With the religion rework, blessings could come from the gods. |
| ITM-03 | Add archer armor. Archers quiver, leather bracers, tunic | Needs decision | P2 | OQ-02 | Design + Art | **Dup cluster** with ITM-04 and the bows/arrows question |
| ITM-04 | Hunters quiver, direct upgrade to base quiver | Needs decision | P2 | OQ-02, OQ-12 | Design | Is "Archers quiver" (ITM-03) the same item as this? |
| ITM-05 | Add more potions for skill bonuses | Idea | P2 | none | Design + Econ | |
| ITM-06 | Make chromium red and vanadium green, swap already used images and recolor existing ones. | Ready for plan | P1 | none | Art | Low risk, art only. Precedent: `swap-titanium-tungsten`. |
| ITM-07 | Add Items that increase lockpick chance | Idea | P2 | SKL-01 | Design | Thievery cluster |

### SKL: Skills and activities

| ID | Title | Status | Pri | Dep | Owner | Notes |
|---|---|---|---|---|---|---|
| SKL-01 | Add Recipe items unique to thievery, loot bags/boxes | Idea | P2 | none | Design + Econ | **Thievery cluster:** SKL-01/02, ITM-07, QST-07, MAP-03 |
| SKL-02 | Higher able thievery companions that can carry out heists for you | Idea | Later | SKL-01 | Design | Companion system is new infrastructure |
| SKL-03 | Reduce base success chance further at higher levels | Idea | P2 | none | Econ | Clarify which skills: thievery only, or all success-chance skills? |
| SKL-04 | Cooking crafts = more than one food | Ready for plan | P1 | none | Econ | Small and helps early food supply |
| SKL-05 | Add fruit trees | Idea | P2 | none | Design | Botany/woodcutting overlap |
| SKL-06 | Tides that effect fishing | Idea | Later | SYS-06 | Design | Uses the server clock |

### ECO: Economy and rewards

| ID | Title | Status | Pri | Dep | Owner | Notes |
|---|---|---|---|---|---|---|
| ECO-01 | Require total level 200 to use the bazaar | Needs decision | P1 | OQ-10 | Econ | Anti-bot/alt measure. **Coupled** with MEM-02. |
| ECO-03 | Replace bounty and pvp gold reward with new currency, plaza points… plaza shop for items and exp | Needs decision | P1 | OQ-15, Game Bible update | Econ | **Blocks** SOC-03 leaderboard payouts (soft) |

### SOC: Social / Competitive

| ID | Title | Status | Pri | Dep | Owner | Notes |
|---|---|---|---|---|---|---|
| SOC-01 | 5 guild hall tiers (bank, boxing ring, indoor garden, arcana station, monster cage) | Idea | P2 | rls-hardening #3–6 (server hall settlement, withdrawals, rank perms) | Design + Systems | Existing tiers: Build the Hall, Counting Room, Boxing Ring. Map the 5 tiers onto these. |
| SOC-03 | Revolving leaderboards for guilds and pvp… monthly reset… temporary title | Idea | P2 | *soft:* ECO-03, TTL system | Community + Econ | Leaderboards already exist and are written from the hosted save |
| SOC-04 | Make bosses solo or mass… scaled by players… contribution drops… lobby queue | Needs decision | Later | OQ-08, realtime infra | Design + Systems | Large: new server lobby system |

### MAP: World and maps

| ID | Title | Status | Pri | Dep | Owner | Notes |
|---|---|---|---|---|---|---|
| MAP-01 | Add a region map. continent map, with regions… | Needs decision | P1 | OQ-01, OQ-11 | Design + UI | **Foundation:** blocks MAP-01b/02/03 |
| MAP-01b | Regions can be unlocked at 200, 400, 800 total level citadel can be in the middle with a persistent travel button on every map *(from UI)* | Needs decision | P1 | MAP-01, OQ-11 | Design | **Dup** with MAP-01 (unlock rule) and MAP-03 (citadel) |
| MAP-02 | Start a new map/region, move the depths there, call it the isles… underwater exploration | Idea | P2 | MAP-01 | Design + Art | "The Depths" is MAP-0009 today |
| MAP-03 | Move citadel to its own 2nd main map… thievery… low level areas but mostly mid to high | Idea | P2 | MAP-01 | Design | **Dup:** UI "Citadel can be its own region, restoria is a old crumbling empire, the citadel is a nearby empire" → merged here (lore part → WLD-02) |
| MAP-04 | Add proper landing nodes for sub maps | Idea | P1 | none (listed under OQ-01) | UI | Partly done? Branch `submap-landing-83f5` exists. Confirm what shipped. |

### WLD: Lore / Races / Religion

| ID | Title | Status | Pri | Dep | Owner | Notes |
|---|---|---|---|---|---|---|
| WLD-01 | Replace races and racial bonus with religious alignments… Vesper can become a religious figure or be replaced by churches/shrines | Needs decision | P2 (decision P1) | OQ-07 | Design + Art + Writer | **Affects:** TTL-03 Pureblooded, Vesper/QST-0009, `Races/RaceBonuses/RaceStartingItems`, race art, ITM-01 blessings, ART-06 |
| WLD-02 | Restoria = old crumbling empire, Citadel = nearby empire (lore) | Idea | P2 | MAP-03 | Writer | Split out of the UI list |

### UI: UI / UX

| ID | Title | Status | Pri | Dep | Owner | Notes |
|---|---|---|---|---|---|---|
| UI-01 | Add images to skill menus | Idea | P2 | ART-01 (spec) | UI + Art | |
| UI-02 | Make skill menus better | Idea | P2 | UI-01 | UI | |
| UI-03 | Fancier font for headers | Idea | P2 | UI-06 | UI | |
| UI-04 | Use more icons for buttons, x icon to replace close button | Idea | P2 | UI-05 | UI | |
| UI-05 | Look for ui asset pack | Ready for plan | P1 | none | Art + UI | Gates UI-03/04/06 |
| UI-06 | Reduce gold borders | Idea | P2 | UI-07 | UI | |
| UI-07 | Choose rules for use of green and gold in ui | Needs decision | P1 | none (Conor decision) | UI | `Master_Prompt.md` §6 says "gold highlights, soft green accents"; formalize it. |
| UI-12 | Bank and inventory tabs for custom organization | Needs decision | P2 | OQ-03, MEM-01 | UI | |
| UI-14 | Language support | Needs decision | Later | OQ-18 | UI | |

### ART: Art direction and animation

| ID | Title | Status | Pri | Dep | Owner | Notes |
|---|---|---|---|---|---|---|
| ART-01 | Art spec sheet: simple backgrounds with a player/action spot; sky 360×360, terrain 360×180, foreground 360×60, player/action 64×96 / 96×64 / 96×96, items/critters 24×24, portraits 64×64, enemies/actions 128×160 | Ready for plan | P1 | none | Art | Write it into the Game Bible art section (agents follow it). Blocks ART-02/04/05, UI-01. |
| ART-02 | The player has simple jumpy animations and throws its weapon or tool to attack; enemies simpler, maybe no outlines | Idea | P2 | ART-01, ART-04 | Art | |
| ART-04 | Setup animations using flame | Idea | P2 | ART-01 | Systems + Art | |
| ART-05 | Instead of 4 tabs on the header, make the log have 4 panels with art the name and the total completion… item collection, monster killing, and more sections | Idea | P2 | ART-01 | UI + Art | |
| ART-06 | Simpler character art (skin tone only) | Needs decision | P2 | WLD-01 | Art | Follows from the religion decision. |

### TTL: Titles

| ID | Title | Status | Pri | Dep | Owner | Notes |
|---|---|---|---|---|---|---|
| TTL-00 | Title system: prefix vs suffix display | Idea | P2 | none | Writer (copy) + Design | Today titles are Wardrobe cosmetics (`ITEM-0301`) |
| TTL-01 | the Undying, suffix, lost after first death | Live (mostly) | ✅ mostly done | TTL-00 | Writer (copy) | Exists. Only the suffix display may be missing. |
| TTL-02 | the Slayer, suffix, 500,000 monster kills | Idea | P2 | TTL-00 | Writer (copy) + Design | Kill statistics exist |
| TTL-03 | Pureblooded, prefix, lost after first race change | Needs decision | P2 | **OQ-07** | Writer (copy) + Design | Meaningless if races are removed. Could become "Devout" / "first alignment change". |

### MEM: Membership QoL

All MEM items need payments infra and a Game Bible change (`Master_Prompt.md`
bans monetization unless it's in the sources). Econ owns the fairness review.

| ID | Title | Status | Pri | Dep | Owner | Notes |
|---|---|---|---|---|---|---|
| MEM-01 | Bank space | Needs decision | Later | OQ-06, OQ-03 | Econ | |
| MEM-02 | Instant access to the bazaar at total level 1 | Needs decision | Later | OQ-06, ECO-01 | Econ | **Fairness flag:** lets a paying alt skip the anti-bot gate |
| MEM-03 | Pick your name color | Needs decision | Later | OQ-06 | Econ | Name color already exists for free; would it be taken away? |
| MEM-04 | Double afk time | Needs decision | Later | OQ-06 | Econ | 24h → 48h; edge CPU replay cost, see `fafa140e` |
| MEM-05 | 2 extra bazaar slots (4 free) | Needs decision | Later | OQ-06 | Econ | Today **6** free slots; "4 free" would cut what players have now |

### NTF: Notifications

All depend on SYS-05. Owner: Community.

| ID | Event | Status | Pri | Dep | Notes |
|---|---|---|---|---|---|
| NTF-01 | Activity stopped after afk | Idea | P1 | SYS-05 | |
| NTF-02 | Inventory full | Needs decision | P1 | SYS-05, OQ-03 | |
| NTF-03 | Food depleted | Idea | P1 | SYS-05 | |
| NTF-04 | Production queue finished | Idea | P1 | SYS-05 | |
| NTF-05 | Crop ready | Idea | P2 | SYS-05 | |
| NTF-06 | Quest step completed | Idea | P1 | SYS-05, BUG-01 | Needs persisted steps or it fires again and again |
| NTF-07 | Guild invitation | Idea | P2 | SYS-05 | |
| NTF-08 | Direct message | Idea | P2 | SYS-05 | Already partly done via chat bubbles |
| NTF-09 | Someone bought your Bazaar listing | Idea | P2 | SYS-05 | |

### DNG: Dungeons

| ID | Title | Status | Pri | Dep | Owner | Notes |
|---|---|---|---|---|---|---|
| DNG-01 | "The catacombs"… waves of skeletons and zombies… gathering actions… monsters get harder… solo survival / group dungeons with roles / secondary timer | Needs decision | Later | OQ-17, SOC-04 (group tech), SYS-05 | Design | |

### 5.1 Duplicates and overlaps

| Cluster | Items | Agreed handling |
|---|---|---|
| Citadel as region | UI "Citadel can be its own region…", UI "citadel can be in the middle…", MAP-03 | One item, MAP-03. Lore → WLD-02, travel button → MAP-01b |
| Region unlock vs region map | MAP-01b (200/400/800) vs MAP-01 | MAP-01 builds the map, MAP-01b sets the unlock rule (OQ-11) |
| Getting Started | BUG-01 Fennel bug, QST-01 dialogue fix, QST-02 mandatory tutorial | Fix BUG-01 first (small, generic). Then do QST-02 and QST-01 as one design pass. |
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
SYS-01 dialogue system ─► QST-01 dialogue fixes, QST-02 tutorial, QST-03 king/queen
BUG-01 (persist steps) ─► QST-02 tutorial, NTF-06 quest-step notifications
OQ-15 + Bible ─► ECO-03 plaza points ─► bounty/pvp reward swap, SOC-03 leaderboard payouts
SYS-05 notifications ─► NTF-01..09
ARC-01 tablets ─► ARC-07 piercing, ARC-08 shield
ARC-02 essence rework ─► ARC-03 spell charges, ARC-04 essence item
OQ-07 religion ─► WLD-01 ─► TTL-03 Pureblooded, Vesper/QST-0009, ITM-01 blessings, ART-06
OQ-03 inventory size ─► UI-12 tabs, MEM-01 bank space, NTF-02
OQ-05 untradeable ─► BUG-02, QST-12, ARC-01
ADM-01 audit ─► ADM-02 email, ADM-03 dashboard ─► ADM-05 telemetry
rls-hardening #3–6 (server hall settlement) ─► SOC-01 guild hall tiers
UI-07 color rules + UI-05 asset pack ─► UI-03/04/06
ART-01 spec ─► ART-02/04/05, UI-01
```

---

## 6. Done archive

Moved here with PR and date once `Live`. Seeded with work that was already done
when the backlog was approved.

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

---

## Appendix A: Fennel "Getting Started" bug analysis

Supports **BUG-01**. Analysis only; no fix has been implemented.

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

**Probably affects other quests too:** any quest with a `Hold:` step followed by
steps that use up or move that item has the same problem. Worth an audit (QA
bot): grep `Hold:` in `QuestSteps`.

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

| Bot | Scope | Inputs | Owns sections | Must escalate to Conor |
|---|---|---|---|---|
| **Ops/Security** | Supabase (advisors, RLS, logs, migrations test→live), Cloudflare Workers/DNS, edge CPU, secrets hygiene, auth/email, admin dashboard, telemetry | Supabase + Cloudflare connectors (read first), `rls-hardening.md`, `deployment.md`, `server-authority.md` | ADM, rls follow-ups | Any live migration, auth setting change, secret rotation, cost/plan change, data deletion |
| **QA/Bugfix** | Repro, root cause, parity tests, regression audits (e.g. the `Hold:` audit), playtest checklists | Bug reports, Discord/report button, PRs | BUG | Fix choice when it changes player-facing behavior, save repairs, exploit disclosure |
| **Game Design/Systems** | Specs for core systems (dialogue engine, travel, inventory, notifications plumbing, maps, tablets, bosses, dungeons) | Game Bible, DB, backlog | SYS, MAP, ARC (with Econ), DNG, SOC-01/04 | Every open question. Any new system or currency. Changes to Master_Prompt §10 rules. |
| **Content/Quest & Dialogue writer** | Quest steps, NPC dialogue, lore, titles copy | Dialogue engine, Game Bible lore | QST, WLD-02, TTL copy | New lore canon (king/queen dragon, religions), reward values |
| **Economy/Balance** | Sell values, tradeability, drops, XP, Bazaar gates, plaza points, membership fairness, potions | DB values, Bazaar/leaderboard data | ECO, SKL balance, ITM stats, MEM fairness review | Any currency, membership perk, reward-value change, the "untradeable" definition |
| **UI/UX** | Menus, icons, fonts, color rules, tabs, landing nodes, language | Flutter `app_flutter/lib/src/ui`, ART spec | UI, MAP-04, notifications UI | Style rules (green/gold), asset-pack purchase/licence |
| **Art Direction** | Asset spec, generation/sourcing, recolors, Flame animations | ART spec, Master_Prompt §6 | ART, ITM-06, ART-06 | Style changes, new asset categories, paid assets |
| **Community/Notifications** | Notification events and delivery, Discord webhook, leaderboard seasons, player update mails | SYS-05, Discord, leaderboards | NTF, SOC-03, ADM-04 (with Ops) | Push-permission prompts, season rewards/titles, public announcements |
