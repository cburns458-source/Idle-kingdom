# SYS-01 Dialogue Screen — UI Spec

Status: **approved; first UI pass built** (see §8). §1–§5 are the full design; §8 says which parts are in the game now and which are still to come. Reuses existing `Palette`, `GameFont`, `GamePanel`, `GameButton`, `chromeSlotFill`, `ItemIcon` and PixelChrome. **No new colours or fonts** (colour rules paused).
Source read: `cburns458-source/Idle-kingdom` @ `4f5abbc` (Oct 12 2026).

## 1. Current state
- `app_flutter/lib/src/ui/npc_panel.dart` — `NpcPanel` (opened from `location_view.dart:655`, `NpcOpen`). Branches per NPC state (talk/donate/accept/turn-in/bribe/combat/mentor/whereabouts/tanner/race change) and renders each via `_playerDialogue()` → private `_DialogueCard` (l.635): `GamePanel` + `NpcPortrait(68)` + name (`GameFont.l`) + line (`GameFont.m`) + optional `detail` (`MutedText`), quest journal (`_QuestMenuLine`, ✓/• rows), `extra`, error (`Palette.danger`, `GameFont.s`), and a right-aligned `Wrap` of `GameButton`s.
- `app_flutter/lib/src/ui/dialogue_window.dart` — `DialogueWindow` is a **duplicate** of `_DialogueCard` ("extracted look") for the standalone engine; `StandaloneDialogueHost` calls `startDialogue`/`chooseDialogue` and commits `dialogue_choose`. NpcPanel reaches it via the "Something else…" button (`_withStandalone`, only `ids.first`).
- `src/game/dialogue/engine.ts` — `DialogueView {dialogueId,nodeId,speakerName,npcId,line,choices[{choiceId,label}],finished}`; unknown/failed conditions **hide** choices; result has a free-text `message`, no structured item deltas.
- Rewards today: item gains surface only as `controller.announce(message)` text or `showQuestRewards` popup (`npc_panel.dart`, string list).
- Reusable pieces: `IngredientChip` (`ingredient_chip.dart`: `chromeSlotFill` + `ItemIcon(18)` + count), `RewardStrip._Chip` (`reward_strip.dart`), `QuestHintPulse` (`theme.dart:1101`), `GameButton` min heights 32 / compact 28 / tiny 24 (`theme.dart:436-439`), popup size consts 320×360 (`game_popup.dart:24-25`).
- Gaps: two copies of the card; no item chips; no locked-choice display; no quest marker; no text reveal; panel height jumps with line length; touch targets 28–32 px (below 44–48 px mobile guidance).

## 2. Layout (single shared panel)
```
┌ GamePanel (fixed size) ──────────────────────┐
│ [NpcPortrait 68]  Speaker name (GameFont.l)   │  header, fixed
│───────────────────────────────────────────────│
│ Line text (GameFont.m), revealing…            │  body: fixed height,
│ [ItemIcon +1 Lockpick] [ItemIcon −5 Raw Potato]│  scrolls internally
│ detail / journal / extra (legacy slots)       │
│ error (Palette.danger, GameFont.s)            │
│───────────────────────────────────────────────│
│ [⚑ Accept the job      ]                      │  choices: full-width
│ [  Ask about the ridge ]                      │  stacked buttons
│ [  Pick the lock  (Needs Thievery 25)] greyed │
│                          ▼ tap to continue    │  advance hint
└───────────────────────────────────────────────┘
```
- Fixed panel: width = existing panel width; body height fixed (proposal: fits ~5 lines of `GameFont.m`); longer lines scroll inside the body, panel never resizes between lines.
- Choices stacked vertically, full width, `GameButton` primary for first/quest choice, `secondary` for others (existing tones). Min touch height 44 px on touch platforms (via padding/`ConstrainedBox`, not new styles). Legacy compact buttons ("Browse the shop", "Done") keep current tones but get the same min height on mobile.
- Max 4 choices visible; more scroll within the choice area.

## 3. Components (new / changed)
| Widget | File | Change |
|---|---|---|
| `DialoguePanel` (new, public) | `ui/dialogue_panel.dart` (new) | The one shared card. Props: `npcId, speakerName, line, items: List<DialogueItemDelta>, choices: List<DialogueChoiceModel>, detail?, journal?, extra?, error?, message?, onChoose, onClose, revealKey`. Replaces `_DialogueCard` and `DialogueWindow` body. |
| `DialogueChoiceModel` (new) | same | `{id, label, enabled, lockedReason?, questMarked, tone, onPressed}`. Legacy NpcPanel actions map to this (enabled, no reason). |
| `DialogueItemChip` (new) | `ui/dialogue_panel.dart` | `chromeSlotFill` + `ItemIcon(18)` + `+N Name` / `−N Name`; gain text `Palette.parchmentText`/`skillXp`, loss `Palette.danger` (existing colours, same pattern as `IngredientChip` short state). Tooltip = item name. |
| `RevealText` (new) | `ui/dialogue_panel.dart` | Typewriter reveal of `line`; see §4. |
| `_DialogueCard` | `ui/npc_panel.dart` | Delete; `_playerDialogue` builds `DialoguePanel`. `GameButton` action lists become `DialogueChoiceModel`s (or panel keeps an `actions` escape hatch for one release). |
| `DialogueWindow` | `ui/dialogue_window.dart` | Becomes thin adapter `DialogueView → DialoguePanel`; `StandaloneDialogueHost` keeps engine calls, passes item deltas + choice reasons; empty/error states use panel. |
| Quest marker | deferred | **Decided by Conor: wait for the asset pack.** No placeholder icon (the `!` hint mark is not used); no new colours or fonts. Quest-marked choices render as normal choices until the asset-pack quest icon lands, then it is shown inside `QuestHintPulse(enabled:false)`. |
| Engine view (dependency, Game Systems) | `src/game/dialogue/engine.ts` + Dart `ik_rules` twin | Needs: `choices[].enabled`, `choices[].reason`, `choices[].questMarked` (any `start_quest`/quest step action or `quest_*` condition), `hidden` choices omitted from view; result `itemDeltas: [{itemId, qty}]` for the node just applied. UI must not parse `message` text. |

## 4. Behaviour & states
- **Text reveal:** line reveals at ~40 chars/s (no sound). Tap anywhere on the panel (outside buttons) while revealing → show full line instantly. Choices render immediately but are **disabled until reveal completes** (prevents mis-taps); item chips appear with the full line. Setting/accessibility: respect `MediaQuery.disableAnimations` → no reveal. Already-seen nodes show instantly.
- **Advance:** node with a single "Continue"-type choice (or no choices and not finished): tap anywhere advances; show `▼` hint bottom-right. Nodes with ≥2 choices: tap-anywhere only completes the reveal, never picks a choice.
- **Item handoff:** chips shown under the line of the node where the action applied (from `itemDeltas`); also announced as today. Multiple deltas wrap. Unknown item → `ItemIcon(null)` + "Unknown item".
- **Locked choice:** `enabled:false` → `GameButton(onPressed:null)` (existing disabled look) with reason appended in `GameFont.s`/`Palette.muted`, e.g. "Needs Thievery 25". Tapping shows the reason as a tooltip/announce; no engine call.
- **Hidden choice:** not in the view, not rendered, no placeholder.
- **Quest choice (after asset pack):** quest glyph leading the label; locked quest choices keep the glyph (greyed).
- **States:** loading (start pending, sync today, show nothing extra); normal; locked choices; **no choices + finished** → single "Close"; **empty** (dialogue has no node/line) → panel with "They have nothing to say right now." + Close; **start error** → existing danger text + Close (`StandaloneDialogueHost` today); **choose error** (`ok:false`) → danger text under line, choices stay, no state change; **commit rejected by server** (including a dropped connection) → same as choose error, view rolls back to last confirmed node. There is no offline play mode.
- **Close:** Close/Done always reachable; system back closes the panel.

## 5. Acceptance criteria
1. `_DialogueCard` and `DialogueWindow`'s duplicated build are gone; NpcPanel and StandaloneDialogueHost both render `DialoguePanel` (grep shows one implementation).
2. All existing NpcPanel flows (accept, donate, turn-in, bribe, combat, mentor, whereabouts, tanner, race change, shop) look and behave as before apart from button height/stacking.
3. Grant/take actions show `+N`/`−N` chips with icon on that node; take shown as loss.
4. Choices failing conditions render disabled with the engine's reason text; `hidden` choices never appear.
5. Choices that start/advance a quest show the quest glyph once the asset-pack icon exists (none before then).
6. Panel size is constant across nodes of different line lengths (widget test: same `Size` for 1-line and 8-line nodes); long text scrolls.
7. On touch layouts every choice target ≥44 px tall; tap-anywhere completes reveal, then advances single-continue nodes; never selects among multiple choices.
8. Reveal skippable; disabled when animations are disabled.
9. Empty, start-error, choose-error states render with a Close and no crash.
10. No new `Color(...)` or font definitions added; only `Palette`/`GameFont`/PixelChrome used.
11. Widget tests for locked/hidden/quest/item-chip/empty/error states.

## 6. Engine contract (confirmed by Game Systems, SYS-01 engine spec, merged in PR #315)
- Each choice carries `enabled`, `reason`, `hidden` and `questMarked` (auto when the choice starts/advances a quest; content may also set it).
- `hidden` choices the player can't pick are omitted from the view. A `hidden` choice that is still in the view is pickable and is drawn like any other; the UI also drops any `hidden` choice that is not `enabled`.
- The view carries `stepProgress`: one group per Show / HandIn step its choices check or act on, `{questId, stepId, mode, done, items: [{itemId, have, handedIn, need, mode}]}` (`stepProgressView` returns the `items`). `have` is the bag only, favourited stacks included.
- Each result carries `itemDeltas: [{itemId, qty}]` (+ given, − taken), `bookDeltas`, `stepProgress` (the steps the choice touched) and, on failure, a `code`: `no_room` (with `noRoom: {slotsNeeded, slotsFree}`), `missing_items` (with `missing: [{itemId, have, need}]`), `nothing_to_hand_in`, `not_available`, `invalid`, `action_failed`, `not_found`, `confirm_favourites` (with `favourites: [{itemId, count}]`, sent as `{itemId, qty}`).
- `chooseDialogue(..., useFavourites: true)` / the `dialogue_choose` arg `useFavourites: true` is the player's yes to taking from favourited stacks, for that one request only. It is never written to the save.
- The engine's `reason`, `message` and prompt strings are placeholders. **The UI never shows or parses them**; every string is built from codes, counts and content names (§8).
- TS engine and Dart twin produce these identically; shared test cases cover them.

## 7. Defaults and open questions
Proposed defaults apply unless Conor objects: reveal ~40 chars/s, on by default, skippable, off when animations disabled, instant for seen nodes; fixed body height ~5 lines of `GameFont.m`; full-width stacked choices on desktop too.

Open for Conor: none. (Quest glyph decided: wait for the asset pack, no placeholder.)

Minor follow-ups (non-blocking): spoiler-hiding of locked reasons; NpcPanel "Something else…" listing all available dialogues instead of `ids.first`.

## 8. Built: first UI pass (hand-in, show, full bag, favourites)
Files: `app_flutter/lib/src/ui/dialogue_window.dart` (`DialogueWindow`, `StandaloneDialogueHost`), `app_flutter/lib/src/ui/dialogue_text.dart` (`DialogueText`, every player-facing dialogue string), `app_flutter/test/dialogue_window_test.dart`. UI only: no quest rules, content data, save format or SQL changed.

### Text (built from codes and counts; item names from `Items`)
| Where | When | Text |
|---|---|---|
| Progress line | HandIn step, per item | `Baked Potato 6/10 handed in` (`handedIn`/`need`) |
| Progress line | Show step, not done | `Baked Potato: you have 3/5` (`have`/`need`) |
| Progress line | Show step, done | `Baked Potato: Shown ✓` |
| Choice label | `hand_in` choice, some still wanted in the bag | `Hand in 4 Baked Potato` — per item `min(have, need − handedIn)`; several items joined with "and" |
| Choice label | `hand_in` choice, none of the still-wanted items in the bag | `Bring Baked Potato (6/10 handed in)` |
| Choice label | `hand_in` choice, step done | `Handed in ✓` |
| Choice label | `show_items` choice | `Show 5 Baked Potato` (`need`), then `Shown ✓` once the step is done |
| Popup (OK) | `no_room` | `Your bag is full. Make room for N more items and try again.` N = `slotsNeeded` (new slots only; stacks already in the bag cost none). "1 more item" when N = 1. |
| Popup (Yes / No) | `confirm_favourites` | `Some items are favourited. Do you still want to use them?` then every `favourites` entry: `Baked Potato x4, Cooked Perch x2` |
| Under the line | `missing_items` | `You need 5 Baked Potato (you have 3).` per missing item |
| Under the line | `nothing_to_hand_in` | `You have no Baked Potato to hand in.` (items still wanted) |
| Under the line | `not_available` | `That isn’t available right now.` |
| Under the line | `action_failed` | `That can’t be done right now.` |
| Under the line | `invalid`, `not_found`, other | `That conversation can’t go on right now.` |
| Start failure | `not_available` / other | `They have nothing to say right now.` / `That conversation could not be started.` |
| Announcement | success | Built from `stepProgress`, `itemDeltas`, `bookDeltas`, gold and quest status changes, e.g. `Shown ✓`, `Baked Potato 10/10 handed in. Received 1 Golden Spud.`, `Quest started: …` |

Other choices keep their content `Label`. No dialogue string mentions the bank; only the bag counts.

### Behaviour
- Disabled choices (`enabled: false`) are greyed out (`GameButton(onPressed: null)`); no reason text is drawn, because `reason` is engine placeholder text. Hidden choices are not drawn (§6).
- Favourites never grey out, relabel or hint a hand-in / take-item choice. Counts include favourited stacks.
- One request at a time: a choice is ignored while one is in flight, and until the next frame after it settles, so a double tap sends one request.
- `confirm_favourites`: **No** closes the prompt and does nothing. **Yes** resends the same choice once with `useFavourites: true` (the local engine call and the `dialogue_choose` command arg). The flag is not stored; the next choice asks again. If the resend fails (for example `no_room`), that failure is shown; the favourites prompt is never reopened for the same tap.
- `no_room`: popup only; the dialogue stays on the same node with no inline error.
- Progress the last choice touched stays listed on the next node when that node does not reference the step, so `Shown ✓` / the new hand-in count stays visible.

### NPC quest panel (legacy Turn in / hand-in)
The same popups are used from `NpcPanel` when the player taps **Turn in** (the non-dialogue quest panel). Text still comes from `DialogueText`; the widgets are `showDialogueBagFullPopup` and `showDialogueFavouritesPrompt` in `dialogue_window.dart`.

- `no_room` on that tap shows the bag-full popup. N is `slotsNeeded` (new slots only). Nothing is committed.
- `confirm_favourites` shows the Yes/No prompt and lists every `{itemId, count}` as `Name xN`. **No** cancels. **Yes** resends the same `quest_complete` once with `useFavourites: true`. The flag is never saved.
- Turn in is never greyed out because items are favourited.
- A quest that completes on its own (visit / talk auto-complete) and hits a full bag waits for the next visit: no popup.

### Still to come (not in this pass)
Shared `DialoguePanel` replacing `_DialogueCard` in `npc_panel.dart`, item chips, text reveal, tap-to-advance, fixed panel height, stacked full-width / 44 px choices, locked-reason text (needs non-placeholder engine wording or UI wording per condition), quest glyph (waits for the asset pack).

### Tests (`app_flutter/test/dialogue_window_test.dart`, content + the SYS-01 parity patch)
Hand-in progress and label; "Bring …" with none in the bag (bank stock ignored); hand-in commit; Show progress, label, missing-items text and `Shown ✓`; bag-only counts; disabled greyed and hidden not drawn; favourites never grey out or hint; double tap sends one request (pending request and local engine); full-bag popup counts new slots only; `confirm_favourites` lists every entry, No does nothing, Yes resends once with `useFavourites` and is not remembered; full bag after Yes shows the bag popup without reopening the prompt; each failure code worded by the UI; no dialogue UI string contains "bank".

NPC quest panel (`app_flutter/test/npc_quest_panel_popups_test.dart`): `no_room` popup with the correct N; Yes resends with `useFavourites` exactly once; No does nothing; a double tap sends one request; a full bag after Yes shows the popup; several favourites listed; Turn in stays enabled when items are favourited.
