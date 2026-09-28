#!/usr/bin/env python3
"""Library books, Green Thumb, Weighted Boomerang, Baby Dragon pet, kitchen gate copy."""
from __future__ import annotations

import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "content/data/game-database.json"
ITEM_ICON_DIR = ROOT / "content/assets/icons/items"

NEWCOMER_BODY = """Welcome to Restoria. The land does not rush you, but it does reward those who learn its rhythm.

Open the map, choose a location, and travel there. Once you arrive, look over the activities on offer. Gathering, crafting, cooking, combat, and other work all live in these lists. Each activity draws from its own pool of rewards, so what you earn depends on where you stand and what you choose to do.

Materials gather in your bag. Bring them to a workshop, a forge, a kitchen, or a workbench and shape them into tools, food, and gear. Better equipment shortens your labors and steadies your hand in a fight.

When you want a longer chase, open the Log. Deeds, milestones, and quests wait there to mark what you have done and what still calls. When you want the kingdom’s records of items, enemies, and recipes, open the Codex.

Good luck adventurer!"""

BOTANIST_BODY = """Unlock a plot, plant what you carry, and let the timer run. When the bed is ready, harvest it. Often the earth returns your planting along with a share of the crop. Compost gathered from patches can be worked in when you plant, and it improves your chance of a healthy result. Seeds may shift as they grow, and mutations appear as your Botany rises. Several seeds can share one bed, even mixed kinds, while a sapling asks for the whole plot to itself.

Equip pruners when you gather from woodcutting or harvesting, and the usual drops give way to a chance at seeds instead. The experience you earn from that work becomes Botany experience.

Tend the timers. Harvest when the ground is ready. Plant again!"""

GRAND_FEAST_INTRO = (
    "The feast is days away and my kitchens are in shambles. Ten baked potatoes, "
    "golden and crisp, and ten cooked perch besides. Use the Main Hall kitchen to "
    "cook what you need. Bring them here when they are ready."
)


def upsert(rows: list[dict], key: str, row: dict) -> None:
    existing = next((r for r in rows if r.get(key) == row[key]), None)
    if existing:
        existing.update(row)
    else:
        rows.append(row)


def main() -> None:
    db = json.loads(DB_PATH.read_text())

    # --- Books sheet ---
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
            "Notes": "Granted by Getting Started (QST-0006).",
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
            "Notes": "Granted by Green Thumb (QST-0011).",
        },
    )
    db["Books"] = books

    # --- Quests ---
    for q in db["Quests"]:
        if q["Quest ID"] == "QST-0006":
            notes = q.get("Notes") or ""
            parts = [p.strip() for p in notes.split(";") if p.strip()]
            parts = [p for p in parts if not p.startswith("RewardBook:")]
            if "AutoCompleteOnTalk" not in parts:
                parts.insert(0, "AutoCompleteOnTalk")
            parts.append("RewardBook: BOOK-0001")
            q["Notes"] = "; ".join(parts)
            q["Possible Rewards"] = "Newcomer's Guide"
        if q["Quest ID"] == "QST-0011":
            q["Display Name"] = "Green Thumb"
            q["Internal Key"] = "green_thumb"
            q["Summary"] = "Fennel unlocks the farm patch and asks you to plant a potato seed."
            q["Pitch"] = (
                "You've got a seed. Come to the farm and I'll show you the plot. "
                "Botany starts with putting something in the ground."
            )
            q["Notes"] = (
                "RequiresAnySeed; AutoStartOnSeed; AutoCompleteOnPlant; RewardBook: BOOK-0002"
            )
            q["Possible Rewards"] = "Botanist's Guide"

    for d in db["QuestDialogue"]:
        if d.get("Dialogue ID") == "QDL-0007":
            d["Line"] = GRAND_FEAST_INTRO

    # --- Baby Dragon: cosmetic reward, not critter ---
    for e in db["RewardEntries"]:
        if e.get("Reward Table ID") == "RWT-0180":
            e["Reward Type"] = "Cosmetic"
            e["Reward ID / Value"] = "COS-0012"
            e["Notes"] = "One-time unlock of the Baby Dragon pet cosmetic."
            e["Reward Table Name"] = "Baby Dragon Pet"

    # Keep pet item; strip critter tag implication from description if needed
    for item in db["Items"]:
        if item["Item ID"] == "ITEM-0404":
            item["Display Name"] = "Baby Dragon Pet"
            item["Description"] = "A rare companion that hatches after a dragon falls."
            item["Functional / Source Tags"] = "cosmetic; pet"
            item["Notes"] = "Unlocked the first time a Baby Dragon pet drop is rolled from a dragon."

    for cos in db["Cosmetics"]:
        if cos["Cosmetic ID"] == "COS-0012":
            cos["Acquisition Tags"] = "dragon_drop"
            cos["Notes"] = "Baby Dragon pet. Granted once from dragon kill secondary."

    # --- Weighted Boomerang ---
    bola_icon = ITEM_ICON_DIR / "item_bola.webp"
    boom_icon = ITEM_ICON_DIR / "item_weighted_boomerang.webp"
    if bola_icon.exists() and not boom_icon.exists():
        shutil.copy2(bola_icon, boom_icon)
    elif not boom_icon.exists():
        # fall back to magic bola art
        alt = ITEM_ICON_DIR / "item_magic_bola.webp"
        if alt.exists():
            shutil.copy2(alt, boom_icon)

    upsert(
        db["Items"],
        "Item ID",
        {
            "Item ID": "ITEM-0407",
            "Internal Key": "weighted_boomerang",
            "Display Name": "Weighted Boomerang",
            "Category": "Tool",
            "Subtype": "Hunting tool",
            "Status": "Planned",
            "Release Phase": "Launch",
            "Associated Skill ID": None,
            "Equipment Slot ID": "SLOT-0001",
            "Base Sell Value": 0,
            "Icon Asset Key": "weighted_boomerang",
            "Description": "A heavy hunting boomerang that cuts the wait between casts.",
            "Functional / Source Tags": "hunting_tool; combat_usable; artisanry_output",
            "Notes": "Hunting 70. 20% ATR. Artisanry project. Intentionally deals effectively no damage.",
            "Stackable": None,
        },
    )
    upsert(
        db["Equipment"],
        "Equipment ID",
        {
            "Equipment ID": "EQP-0217",
            "Item ID": "ITEM-0407",
            "Slot ID": "SLOT-0001",
            "Required Skill ID": "SKL-0005",
            "Required Level": 70,
            "Secondary Required Skill ID": None,
            "Secondary Required Level": None,
            "Min Damage": 0,
            "Max Damage": 0,
            "HP Bonus": None,
            "Damage Reduction": None,
            "Healing Amount": None,
            "Action Time Reduction %": 20,
            "Capabilities / Effects": "hunting_tool; combat_usable",
            "Status": "Planned",
            "Notes": "Hunting 70. 20% ATR. Intentionally deals effectively no damage.",
        },
    )
    upsert(
        db["Projects"],
        "Project ID",
        {
            "Project ID": "PRJ-0178",
            "Internal Key": "artisan_weighted_boomerang",
            "Display Name": "Weighted Boomerang",
            "Skill ID": "SKL-0012",
            "Output Item / Target ID": "ITEM-0407",
            "Output Quantity": 1,
            "Facility ID": "FAC-0003",
            "XP Reward": 200000,
            "Gold Cost": 0,
            "Instant": "Yes",
            "Status": "Planned",
            "Release Phase": "Launch",
            "Notes": "Mahogany timber, titanium bars, and leather straps. Instant at the Artisans workshop.",
            "Input 1 Item ID": "ITEM-0218",
            "Input 1 Quantity": 15,
            "Input 2 Item ID": "ITEM-0079",
            "Input 2 Quantity": 2,
            "Input 3 Item ID": "ITEM-0084",
            "Input 3 Quantity": 10,
            "Input 4 Item ID": None,
            "Input 4 Quantity": None,
            "Input 5 Item ID": None,
            "Input 5 Quantity": None,
            "Required Skill 1 ID": "SKL-0012",
            "Required Skill 1 Level": 70,
            "Required Skill 2 ID": None,
            "Required Skill 2 Level": None,
        },
    )

    text = json.dumps(db, indent=2, ensure_ascii=False) + "\n"
    DB_PATH.write_text(text)
    print("patched library bundle content")
    print("  books: BOOK-0001, BOOK-0002")
    print("  quests: Getting Started reward; Green Thumb rename")
    print("  baby dragon: Cosmetic COS-0012")
    print("  weighted boomerang: ITEM-0407 / EQP-0217 / PRJ-0178")


if __name__ == "__main__":
    main()
