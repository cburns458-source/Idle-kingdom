#!/usr/bin/env python3
"""Library pass: rewrite the two guides, add the first found lore book.

House voice for Restoria books
------------------------------
- Calm, second person for guides. Short paragraphs. No exclamation marks.
- Concrete nouns that exist in the game data (kitchen, furnace, food slot).
- No numbers the player cannot already see in the UI; say "often", "a quarter".
- Every claim must match the rules code. If the rule changes, the book changes.
- Attribution varies on purpose: some books are signed by the NPC who hands
  them over (Fennel), some by a named author who exists only on the page
  (Ilsa Wren), and lore books stay anonymous.

Books are unlocked two ways: a quest `RewardBook:` note, or a `Book` reward
entry rolled from an action's reward table. A `Book` entry is a one-time find:
once the book is in the Library the roll grants nothing.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "content/data/game-database.json"

NEWCOMER_BODY = """Welcome to Restoria. The land does not rush you, but it rewards those who learn its rhythm.

Open the map, pick a place, and travel there. Each place offers its own work: gathering, fighting, cooking, crafting. Start one and it carries on by itself, even while you are away, for up to a day.

Your bag fills as you work. Carry it to a kitchen, a furnace, or a workshop and shape it into food, bars, tools, and gear. Better gear means quicker work and shorter fights. The banks in Town and the Citadel hold what you would rather not carry.

Before a fight, put food in your food slot. You eat on your own after each win when you are hurt. If you fall, you lose nothing but half a minute. Some places warn of danger before you go. Heed it, or don't.

The Log keeps your deeds, milestones, and quests. The Codex keeps the kingdom's records of items, actions, and beasts. Other adventurers walk these roads too. You will find them at the Citadel.

— Ilsa Wren, wayfarer"""

BOTANIST_BODY = """Every patch wants the same three things: a seed, some compost, and time.

Plant up to three seeds in a bed, mixed kinds if you like. A sapling wants the bed to itself and takes half a day. Work compost in when you plant: one for a seed, five for a sapling. Not everything you plant will live. New growers lose more than old hands do, and compost is the difference.

When a plant lives, the earth often hands your seed back with the crop. Plant two kinds together and now and then it hands back a third kind that neither of them was. Try pairs. Keep what comes.

Pruners turn harvesting or woodcutting into Botany practice. The usual drops stop, a seed turns up now and then, and a quarter of the experience goes to Botany instead of the skill you were working.

Compost is turned from the patches themselves. My plot here at the farm is yours whenever a bed stands empty. There are others at the castle courtyard once the king has had his feast, at the Citadel outskirts, on the mountain slopes, and at the temple. The bed in the Shallows grows only kelp and wants no compost.

— Fennel"""

COLD_FORGE_BODY = """A loose page, folded into the ledger in a hand that is not the merchant's.

We were not always a shop.

The mountain was ours from the slopes to the deep pools. The forge above the shaft never went dark, and the halls under it rang from one end to the other. We cut iron and coal, and below that the rarer ores, and the sound of it was the sound of a people who did not think they could fall.

Then the shaft came down. Rubble where there had been a road, and no one left who could say why. The forge above went cold waiting for ore that never came. One by one we climbed to the slopes, or went down to the town, and learned to sell what we used to make.

The store is what stayed. A counter, a few pickaxes, and a fair price for ore, so that someone would still bring it up out of the ground.

If you are reading this, your hands are in a dwarf's strongbox. Take the coal. Leave the page, or don't. But if you ever meet a smith who wants the old fire lit, give her what she asks for. Some of us still mean to rebuild."""

BOOK_FIND_TABLE_ID = "RWT-0197"
BOOK_FIND_ENTRY_ID = "RWE-T01970"
STEAL_MINING_MERCHANT_ACTION_ID = "ACN-0192"
BOOK_FIND_CHANCE_PERCENT = 0.1


def upsert(rows: list[dict], key: str, row: dict) -> None:
    existing = next((r for r in rows if r.get(key) == row[key]), None)
    if existing:
        existing.update(row)
    else:
        rows.append(row)


def main() -> None:
    db = json.loads(DB_PATH.read_text())

    books = db.setdefault("Books", [])
    upsert(
        books,
        "Book ID",
        {
            "Book ID": "BOOK-0001",
            "Internal Key": "newcomers_guide",
            "Display Name": "Newcomer's Guide",
            "Body": NEWCOMER_BODY,
            "Status": "Confirmed",
            "Release Phase": "Launch",
            "Notes": "Granted by Getting Started (QST-0006). Signed by Ilsa Wren, a name only.",
        },
    )
    upsert(
        books,
        "Book ID",
        {
            "Book ID": "BOOK-0002",
            "Internal Key": "botanists_guide",
            "Display Name": "Botanist's Guide",
            "Body": BOTANIST_BODY,
            "Status": "Confirmed",
            "Release Phase": "Launch",
            "Notes": "Granted by Green Thumb (QST-0011). Signed by Fennel, who hands it over.",
        },
    )
    upsert(
        books,
        "Book ID",
        {
            "Book ID": "BOOK-0003",
            "Internal Key": "the_cold_forge",
            "Display Name": "The Cold Forge",
            "Body": COLD_FORGE_BODY,
            "Status": "Confirmed",
            "Release Phase": "Launch",
            "Notes": (
                "Anonymous dwarven lore. Rare one-time find (0.1%) while stealing from the "
                f"mining merchant ({STEAL_MINING_MERCHANT_ACTION_ID}, {BOOK_FIND_TABLE_ID})."
            ),
        },
    )

    upsert(
        db["RewardEntries"],
        "Reward Entry ID",
        {
            "Reward Entry ID": BOOK_FIND_ENTRY_ID,
            "Reward Table ID": BOOK_FIND_TABLE_ID,
            "Reward Table Name": "Dwarven Store Page",
            "Purpose": "Secondary output",
            "Reward Type": "Book",
            "Reward ID / Value": "BOOK-0003",
            "Weight": 100,
            "Minimum Quantity": 1,
            "Maximum Quantity": 1,
            "Skill ID": None,
            "XP Amount": None,
            "Status": "Confirmed",
            "Notes": "One-time Library unlock of The Cold Forge. Grants nothing once found.",
        },
    )

    for action in db["Actions"]:
        if action["Action ID"] == STEAL_MINING_MERCHANT_ACTION_ID:
            action["Secondary Drop Chance"] = BOOK_FIND_CHANCE_PERCENT
            action["Secondary Reward Table ID"] = BOOK_FIND_TABLE_ID

    DB_PATH.write_text(json.dumps(db, indent=2, ensure_ascii=False) + "\n")
    print("patched library books")
    print("  books: BOOK-0001, BOOK-0002 rewritten; BOOK-0003 added")
    print(f"  {STEAL_MINING_MERCHANT_ACTION_ID}: secondary {BOOK_FIND_TABLE_ID} at {BOOK_FIND_CHANCE_PERCENT}%")


if __name__ == "__main__":
    main()
