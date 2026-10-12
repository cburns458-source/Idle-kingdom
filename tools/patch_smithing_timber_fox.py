#!/usr/bin/env python3
"""Align smithing timber tiers and set Hunt fox Drop Chance to 30%."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATHS = [
    ROOT / "content/data/game-database.json",
    ROOT / "app_flutter/content/data/game-database.json",
]

# Timber item IDs
CEDAR = "ITEM-0214"
OAK = "ITEM-0215"
POPLAR = "ITEM-0216"
MAPLE = "ITEM-0217"
MAHOGANY = "ITEM-0218"
IRONWOOD = "ITEM-0408"

FOX_ACTION = "ACN-0205"


def _item_id_by_name(db: dict, name: str) -> str:
    for item in db["Items"]:
        if item.get("Display Name") == name:
            return item["Item ID"]
    raise KeyError(name)


def _patch_db(db: dict) -> tuple[int, int]:
    copper = _item_id_by_name(db, "Copper Bar")
    bronze = _item_id_by_name(db, "Bronze Bar")
    iron = _item_id_by_name(db, "Iron Bar")
    steel = _item_id_by_name(db, "Steel Bar")
    reinforced = _item_id_by_name(db, "Reinforced Steel Bar")
    tungsten = _item_id_by_name(db, "Tungsten Bar")
    titanium = _item_id_by_name(db, "Titanium Bar")

    timber_by_bar = {
        copper: CEDAR,
        bronze: OAK,
        iron: POPLAR,
        steel: MAPLE,
        reinforced: MAPLE,
        tungsten: IRONWOOD,
        titanium: MAHOGANY,
    }
    timber_ids = {CEDAR, OAK, POPLAR, MAPLE, MAHOGANY, IRONWOOD}

    timber_changes = 0
    for project in db["Projects"]:
        if project.get("Skill ID") != "SKL-0011":
            continue
        bar_id = None
        timber_slots: list[str] = []
        for slot in ("Input 1 Item ID", "Input 2 Item ID", "Input 3 Item ID", "Input 4 Item ID"):
            item_id = project.get(slot)
            if item_id in timber_by_bar:
                bar_id = item_id
            if item_id in timber_ids:
                timber_slots.append(slot)
        if not bar_id or not timber_slots:
            continue
        want = timber_by_bar[bar_id]
        for slot in timber_slots:
            if project[slot] != want:
                project[slot] = want
                timber_changes += 1

    fox_changes = 0
    for action in db["Actions"]:
        if action.get("Action ID") != FOX_ACTION:
            continue
        if action.get("Drop Chance") != 30:
            action["Drop Chance"] = 30
            fox_changes += 1
        # Visible rate is 30%; no note about the old 1.5× gathering bump.
        notes = "Fox Tail main. Animal Tendons secondary 5%."
        if action.get("Notes") != notes:
            action["Notes"] = notes
            fox_changes += 1
        break

    return timber_changes, fox_changes


def main() -> None:
    for path in PATHS:
        db = json.loads(path.read_text())
        timber_changes, fox_changes = _patch_db(db)
        path.write_text(json.dumps(db, indent=2) + "\n")
        print(f"{path.relative_to(ROOT)}: timber slots {timber_changes}, fox fields {fox_changes}")


if __name__ == "__main__":
    main()
