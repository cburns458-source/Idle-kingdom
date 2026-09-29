#!/usr/bin/env python3
"""Move unused Launch content to Expansion; nudge Citadel / Small Clearing nodes."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB_PATHS = [
    ROOT / "content/data/game-database.json",
    ROOT / "app_flutter/content/data/game-database.json",
]

EXPANSION_NOTE = "Future expansion — hidden from Launch until wired into the world."

ACTIONS = {
    "ACN-0183",  # Dry kelp (legacy placeholder)
    "ACN-0201",  # Cut cinnamon tree
    "ACN-0203",  # Cut heartwood tree (ents still drop heartwood)
    "ACN-0207",  # Hunt sting ray
    "ACN-0209",  # Hunt dire bear
    "ACN-0210",  # Hunt basilisk
    "ACN-0212",  # Mine chromium ore
    "ACN-0213",  # Mine vanadium ore
    "ACN-0217",  # Catch swordfish
    "ACN-0137",  # Chromium bar production
    "ACN-0214",  # Vanadium bar production
    "ACN-0218",  # Cooked swordfish production
}

ITEMS = {
    "ITEM-0384",  # Cinnamon Log (retired)
    "ITEM-0387",  # Cinnamon Bark
    "ITEM-0380",  # Chromium Ore
    "ITEM-0381",  # Vanadium Ore
    "ITEM-0209",  # Chromium Bar
    "ITEM-0382",  # Vanadium Bar
    "ITEM-0392",  # Raw Swordfish
    "ITEM-0393",  # Cooked Swordfish
}

RECIPES = {
    "RCP-0045",  # Chromium Bar
    "RCP-0069",  # Vanadium Bar
    "RCP-0070",  # Cooked Swordfish
}

ENEMIES = {
    "ENM-0028",  # Mage Apprentice
    "ENM-0032",  # Gargoyle
    "ENM-0035",  # Demon
    "ENM-0036",  # Greater Gargoyle
}


def mark_expansion(row: dict, id_key: str) -> bool:
    if row.get("Release Phase") == "Expansion":
        return False
    row["Release Phase"] = "Expansion"
    notes = row.get("Notes")
    if isinstance(notes, str) and EXPANSION_NOTE in notes:
        return True
    if notes is None or notes == "":
        row["Notes"] = EXPANSION_NOTE
    elif isinstance(notes, str):
        row["Notes"] = f"{notes.rstrip('; ')}. {EXPANSION_NOTE}"
    return True


def patch_db(path: Path) -> dict:
    db = json.loads(path.read_text())
    changed = {
        "actions": [],
        "items": [],
        "recipes": [],
        "enemies": [],
        "map_nodes": [],
    }

    for row in db["Actions"]:
        if row["Action ID"] in ACTIONS and mark_expansion(row, "Action ID"):
            changed["actions"].append(f"{row['Action ID']} {row.get('Display Name')}")

    for row in db["Items"]:
        if row["Item ID"] in ITEMS and mark_expansion(row, "Item ID"):
            changed["items"].append(f"{row['Item ID']} {row.get('Display Name')}")

    for row in db["Recipes"]:
        if row["Recipe ID"] in RECIPES and mark_expansion(row, "Recipe ID"):
            changed["recipes"].append(f"{row['Recipe ID']} {row.get('Display Name')}")

    for row in db["Enemies"]:
        if row["Enemy ID"] in ENEMIES and mark_expansion(row, "Enemy ID"):
            changed["enemies"].append(f"{row['Enemy ID']} {row.get('Display Name')}")

    for row in db["MapNodes"]:
        mid = row.get("Map Node ID")
        if mid == "MN-0015":  # Citadel on main map
            if row.get("X") != 38:
                row["X"] = 38
                changed["map_nodes"].append("MN-0015 Citadel main x=38")
        elif mid == "MN-0055":  # Small Clearing on Ancient Forest
            if row.get("X") != 62:
                row["X"] = 62
                changed["map_nodes"].append("MN-0055 Small Clearing x=62")

    path.write_text(json.dumps(db, indent=2, ensure_ascii=False) + "\n")
    return changed


def main() -> None:
    report = None
    for path in DB_PATHS:
        if not path.exists():
            continue
        report = patch_db(path)
        print(f"Patched {path.relative_to(ROOT)}")
    assert report is not None
    print("\n=== Affected (Release Phase → Expansion) ===")
    for section, rows in report.items():
        if section == "map_nodes":
            continue
        print(f"\n{section.upper()} ({len(rows)})")
        for row in rows:
            print(f"  - {row}")
    print("\nMAP NODES")
    for row in report["map_nodes"]:
        print(f"  - {row}")
    print("\nKept Launch: Squidling (ENM-0024), Dried Kelp recipe/item, Heartwood items (ent drops).")


if __name__ == "__main__":
    main()
