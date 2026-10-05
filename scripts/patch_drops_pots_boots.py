#!/usr/bin/env python3
"""Lower willow/yew/weasel primary drops, sapling secondaries, move old boots."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB_PATHS = [
    ROOT / "content" / "data" / "game-database.json",
    ROOT / "app_flutter" / "content" / "data" / "game-database.json",
]

PRIMARY_DROPS = {
    "ACN-0200": (30, "Willow 30% primary."),
    "ACN-0051": (25, "Elder yew 25% primary."),
    "ACN-0015": (30, None),
}

SAPLING_ACTIONS = (
    "ACN-0046",
    "ACN-0047",
    "ACN-0048",
    "ACN-0049",
    "ACN-0050",
    "ACN-0051",
    "ACN-0200",
    "ACN-0202",
)

ROD_BOOT_ACTIONS = (
    "ACN-0099",
    "ACN-0100",
    "ACN-0101",
    "ACN-0102",
    "ACN-0103",
    "ACN-0104",
)


def patch_db(db: dict) -> None:
    for action in db["Actions"]:
        action_id = action.get("Action ID")
        if action_id in PRIMARY_DROPS:
            chance, note = PRIMARY_DROPS[action_id]
            action["Drop Chance"] = chance
            if action_id == "ACN-0015":
                action["Notes"] = "Weasel Tail 100% when the drop rolls (30% drop chance). No tendons."
            elif note:
                notes = action.get("Notes") or ""
                if note not in notes:
                    action["Notes"] = (notes + " " + note).strip()
        if action_id in SAPLING_ACTIONS and action.get("Secondary Reward Table ID"):
            action["Secondary Drop Chance"] = 0.1
            notes = action.get("Notes") or ""
            notes = notes.replace("Sapling secondary 0.5%.", "Sapling secondary 0.1%.")
            if "Sapling secondary 0.1%." not in notes:
                notes = (notes + " Sapling secondary 0.1%.").strip()
            action["Notes"] = notes
        if action_id in ROD_BOOT_ACTIONS:
            action["Secondary Reward Table ID"] = None
            action["Secondary Drop Chance"] = None
            notes = action.get("Notes") or ""
            notes = notes.replace("Old Boots secondary 1%.", "").replace("Old Boots secondary.", "").strip()
            while "Old Boots moved to pot fishing." in notes:
                notes = notes.replace("Old Boots moved to pot fishing.", "").strip()
            action["Notes"] = (notes + " Old Boots moved to pot fishing.").strip()

    for item in db["Items"]:
        if item.get("Item ID") == "ITEM-0347":
            item["Notes"] = (
                "Place at Goblin Camp or the Docks. Up to three pots per site per UTC day, "
                "one at a time; 6 hour soak. Old Boots 1% secondary per collect."
            )


def main() -> None:
    for path in DB_PATHS:
        db = json.loads(path.read_text())
        patch_db(db)
        path.write_text(json.dumps(db, indent=2, ensure_ascii=False) + "\n")
        print(f"patched {path}")


if __name__ == "__main__":
    main()
