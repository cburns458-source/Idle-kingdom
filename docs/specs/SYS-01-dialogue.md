# SYS-01 — Data-driven dialogue engine for all NPCs and quest steps

Status: **Draft / Awaiting Approval**. Spec only, nothing is implemented. Owner: Game Systems. Code base: `test-launch` @ 504b09471.

## 1. What exists today (verified in repo)

| Piece | File | Notes |
|---|---|---|
| Dart engine | `packages/ik_rules/lib/src/dialogue/engine.dart` | `dialogueAvailable`, `dialoguesForNpc`, `startDialogue`, `chooseDialogue`. Header says "QuestDialogue / NpcPanel stay untouched". |
| **TS twin (exists)** | `src/game/dialogue/engine.ts` (+ `engine.test.ts`) | Same exports. The test drives it through `applyGameCommand`. |
| Server command | `src/game/server/authority.ts` → `case 'dialogue_choose'` | Already server-authoritative via Supabase `supabase/functions/game/index.ts` (`action: 'command'`, CAS on `player_saves.version`). |
| Dart tests | `packages/ik_rules/test/dialogue_engine_test.dart` | |
| UI | `app_flutter/lib/src/ui/dialogue_window.dart` (`DialogueWindow` + controller host), legacy `app_flutter/lib/src/ui/npc_panel.dart` | |
| Legacy talk | `QuestDialogue` sheet (28 rows: Dialogue ID, Quest ID, NPC ID, Line) + `quest_talk` command; `currentStepTalkKey` in `packages/ik_rules/lib/src/quests/steps.dart` | |
| Content | `content/data/game-database.json`: `Dialogues` (1 row, DLG-0001 Citadel Guide), `DialogueNodes`, `DialogueChoices` (3 rows) | |
| Save | `completedDialogueIds` (Dart `save_models.dart`, TS `src/game/save/migrations.ts`); `saveVersion = 61` | |

Current limits: one condition (`has_item:<id>` only, unknown → false), one action (`grant_item:<id>:<n>` only), one-time completion only.

## 2. Goals
1. One engine drives every NPC conversation and every quest Talk step.
2. Conditions and actions are data (sheet columns), not code per NPC.
3. Dart and TS produce identical results (parity tests); the server is the only writer.

## 3. Grammar

`Condition` and `Action` columns accept several entries separated by `;`. Whitespace trimmed, empty entries ignored.

### Conditions (all must hold — AND)
| Token | Meaning |
|---|---|
| `quest_active:QST-x` | quest status `active` |
| `quest_step:QST-x:QSTP-y` | QSTP-y is the current step of QST-x |
| `quest_done:QST-x` | quest status `completed` |
| `dialogue_done:DLG-x` | DLG-x in `completedDialogueIds` |
| `has_item:ITEM-x[:n]` | inventory qty ≥ n (default 1). Inventory only, not bank. |
| `total_level:n` | `totalLevel(save) ≥ n` (`skills/totals.dart` / `src/game/skills/totals.ts`) |
| `skill:SKL-x:n` | skill level ≥ n |
| `flag:key` / `!flag:key` | `dialogueFlags` set / not set |
| `!` prefix on any token | negation (e.g. `!quest_done:QST-0006`) |

Unknown token → **false** and a content-validator error (`src/game/data/validate.ts`) so typos fail CI, not players.

### Actions (applied in order, all-or-nothing)
| Token | Effect |
|---|---|
| `grant_item:ITEM-x:n` | existing; uses `inventory/add_items` (fails if no space) |
| `take_item:ITEM-x:n` | remove n from inventory; fails if short |
| `start_quest:QST-x` | same path as `quest_accept` (respects quest requirements) |
| `talk_flag:QST-x:QSTP-y` | satisfies a `Talk:` step — calls the same step-completion path as `quest_talk` |
| `set_flag:key` / `clear_flag:key` | writes `dialogueFlags` |

**All-or-nothing:** actions run on a working copy; if any fails the save is returned unchanged with `ok:false` and the reason (e.g. "Your pack is full."). Conditions are re-checked server-side at choose time, never trusted from the client.

## 4. Data changes
- `Dialogues` add **`Priority`** (int, default 0) and **`Condition`** (gate on the whole dialogue). `dialoguesForNpc` returns available dialogues sorted by Priority desc, then Dialogue ID. NPC click opens the top one; others shown as choices ("Ask about…").
- `DialogueChoices.Condition/Action` keep their names, now multi-token.
- `QuestSteps` unchanged; Talk steps are fulfilled by `talk_flag` from a dialogue whose Condition is `quest_step:...`.

## 5. Save: v61 → v62
- New field `dialogueFlags: string[]` (sorted, unique), default `[]`.
- Migration in both `packages/ik_rules/lib/src/save/migrations.dart` and `src/game/save/migrations.ts`; regenerate `save/generated/save_models.dart`; bump `saveVersion` to 62; add fixture to `save_parity_test.dart`.
- No data loss: `completedDialogueIds` kept as-is.

## 6. Interaction with BUG-01 (option A, being built by QA)
QA is building option A: completed steps are latched as `step:<stepId>` entries in the quest progress counters so a step never reverts (branch `fix/bug-01-latch-quest-steps`). This spec depends on it:
- `quest_step:` must read the latched current step (via `getCurrentStepId`), so dialogue cannot re-offer a finished step.
- `talk_flag` writes the latch through the same helper — no second write path. **Do not start SYS-01 code until the BUG-01 PR merges into test-launch.**

## 7. Server authority & parity
- Only `dialogue_choose` (and a new read-only `dialogue_start` view helper) mutate; client calls `applyGameCommand` via the game function. Offline/local path uses the Dart twin.
- Parity: shared JSON fixtures under `parity/fixtures/dialogue/` (condition matrix, multi-action success, rollback on failure, priority ordering) run by both `packages/ik_rules/test/dialogue_engine_test.dart` and `src/game/dialogue/engine.test.ts`.

## 8. Open decisions (recommended default in bold)
| # | Question | Recommended default |
|---|---|---|
| D1 | Can dialogue give and take items? | **Yes, both** (`grant_item`/`take_item`), all-or-nothing. Rewards that matter economically stay on quest completion; dialogue items limited to quest items/tokens unless Economy signs off (ties to OQ-05). |
| D2 | Replace or run alongside QuestDialogue / NpcPanel? | **Alongside, then replace.** Engine takes priority when an NPC has an available dialogue; else fall back to legacy. Migrate NPC by NPC, delete `QuestDialogue` once empty. |
| D3 | Do players keep tutorial progress through the Getting Started (QST-0006) rewrite? | **Yes.** Keep quest/step IDs; new dialogues gated on `quest_step:` so in-progress players resume at their latched step; completed players see only post-quest lines. |
| D4 | First NPCs | **Fennel (NPC-0014) and the King (NPC-0001)**, then Citadel Guide already on the engine. |

## 9. Files touched (planned)
Dart: `packages/ik_rules/lib/src/dialogue/engine.dart`, `.../save/migrations.dart`, `.../save/generated/save_models.dart`, `.../quests/steps.dart` (shared talk helper), `packages/ik_content` row types (Priority/Condition).
TS: `src/game/dialogue/engine.ts`, `src/game/server/authority.ts`, `src/game/save/migrations.ts`, `src/game/data/types.ts`, `src/game/data/validate.ts`.
Content: `content/data/game-database.json` (+ copy in `supabase/functions/_shared/`).
UI (with UI/UX): `app_flutter/lib/src/ui/dialogue_window.dart`, `npc_panel.dart` (route to engine first).
Tests: `dialogue_engine_test.dart`, `engine.test.ts`, `save_parity_test.dart`, new `parity/fixtures/dialogue/*`.

## 10. Acceptance criteria
1. `a;b;c` conditions evaluate as AND; every token in §3 covered by a test in both languages.
2. A choice with `take_item` the player can't pay, or `grant_item` with full pack, leaves the save byte-identical and returns a reason.
3. `talk_flag` completes a Talk step exactly like `quest_talk`; step never reverts (BUG-01 latch).
4. Highest-Priority available dialogue opens on NPC click; ties sort by ID.
5. v61 saves load as v62 with `dialogueFlags: []`; parity fixture passes in Dart and TS.
6. Unknown tokens fail content validation.
7. Fennel and King run fully on the engine on test.restoriaidle.com with no legacy lines duplicated.

## Review notes folded in (Oct 12)
- UI/UX: show item handoffs inline with icon and amount (+1 / -5); show locked choices greyed out with their reason unless marked `hidden`; add a quest icon on choices that start or advance a quest; tap-to-advance with a fixed-size panel; one shared dialogue panel for NpcPanel and the new engine. Engine impact: each choice exposes a failed-condition reason string and an optional `hidden` flag.
- Economy: every `grant_item` must be one-time, guarded by `dialogue_done` or a flag. The content validator rejects a repeatable grant unless the row is marked `repeatable`. Keep a list of items granted through dialogue for Economy's sell-value review. Quest items should become untradeable once OQ-05 is decided.
- Quest & Dialogue will confirm which quest unlocks which region before MAP-01 is final.

## Engine output contract for the UI (matches UI/UX dialogue screen spec)
- Each choice view includes `enabled` (bool), `reason` (string or null, the first failed condition rendered for players, e.g. "Needs Thievery 25"), and `questMarked` (true when its actions include start_quest or talk_flag, or the row sets `QuestMarker`).
- Choices whose conditions fail and that are flagged `hidden` are left out of the view entirely.
- Each choose result carries `itemDeltas: [{itemId, qty}]`, positive for granted and negative for taken, built from the applied actions. The UI never parses message text.
- These fields are produced identically in Dart and TS, and the parity fixtures cover them.

## Conor's decisions (Oct 12)
- Dialogue may give and take items (grant_item and take_item are approved). Every grant is one-time unless marked `repeatable`.
- Grand Feast hand-in takes 10 Baked Potato and 10 Cooked Perch.
- Getting Started end: Fennel only checks for the cooked potatoes and takes nothing.
- The quest marker icon waits for the asset pack. `questMarked` still ships in the engine output, and the UI can ignore it until then.
