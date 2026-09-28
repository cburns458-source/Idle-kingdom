#!/usr/bin/env python3
"""Kingsroad bandits, Apothecary shop row, and related content wiring."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "content/data/game-database.json"

# Between Farm (76,65) and Town (28,50).
KINGSROAD_X = 52
KINGSROAD_Y = 58


def upsert(rows: list[dict], key: str, row: dict) -> None:
    existing = next((r for r in rows if r.get(key) == row[key]), None)
    if existing:
        existing.update(row)
    else:
        rows.append(row)


def main() -> None:
    db = json.loads(DB_PATH.read_text())

    upsert(
        db["Locations"],
        "Location ID",
        {
            "Location ID": "LOC-0052",
            "Internal Key": "kingsroad",
            "Display Name": "Kingsroad",
            "Map ID": "MAP-0001",
            "Location Type": "Combat Area",
            "Node ID": "NODE-0052",
            "Status": "Planned",
            "Release Phase": "Launch",
            "Description": "The road between farm and town — bandits prey on travelers here.",
            "Danger / Hostility": "Danger warning: approximately Combat Level 9.",
            "Background Asset Key": "locations/loc_forest_path.webp",
            "Parent Location ID": None,
            "Landing Location ID": None,
            "Notes": None,
        },
    )

    upsert(
        db["MapNodes"],
        "Map Node ID",
        {
            "Map Node ID": "MN-0057",
            "Map ID": "MAP-0001",
            "Location ID": "LOC-0052",
            "X": KINGSROAD_X,
            "Y": KINGSROAD_Y,
            "Status": "Planned",
            "Notes": "Between Farm and Town.",
        },
    )

    upsert(
        db["Actions"],
        "Action ID",
        {
            "Action ID": "ACN-0235",
            "Internal Key": "fight_bandit",
            "Display Name": "Fight bandit",
            "Category": "Combat",
            "Relevant Skill ID": "SKL-0001",
            "Target Type": "Enemy",
            "Target ID": "ENM-0026",
            "XP Reward": 520,
            "Drop Chance": 0,
            "Reward Table ID": None,
            "Status": "Planned",
            "Release Phase": "Launch",
            "Notes": "No drops. Enemy record owns HP, damage, and gold.",
        },
    )
    upsert(
        db["Actions"],
        "Action ID",
        {
            "Action ID": "ACN-0236",
            "Internal Key": "fight_bandit_captain",
            "Display Name": "Fight bandit captain",
            "Category": "Combat",
            "Relevant Skill ID": "SKL-0001",
            "Target Type": "Enemy",
            "Target ID": "ENM-0029",
            "XP Reward": 2268,
            "Drop Chance": 0,
            "Reward Table ID": None,
            "Status": "Planned",
            "Release Phase": "Launch",
            "Notes": "No drops. Enemy record owns HP, damage, and gold.",
        },
    )

    upsert(
        db["PoolEntries"],
        "Pool Entry ID",
        {
            "Pool Entry ID": "PEN-0120",
            "Pool ID": "POOL-0062",
            "Action ID": "ACN-0235",
            "Weight": 80,
            "Status": "Planned",
            "Notes": "Bandit 80%.",
        },
    )
    upsert(
        db["PoolEntries"],
        "Pool Entry ID",
        {
            "Pool Entry ID": "PEN-0121",
            "Pool ID": "POOL-0062",
            "Action ID": "ACN-0236",
            "Weight": 20,
            "Status": "Planned",
            "Notes": "Bandit Captain 20%.",
        },
    )

    upsert(
        db["Activities"],
        "Activity ID",
        {
            "Activity ID": "ACT-0081",
            "Internal Key": "fight_bandits",
            "Contextual Name": "Fight the bandits",
            "Location ID": "LOC-0052",
            "Description": "Hostile bandit combat on the Kingsroad.",
            "Danger Warning Combat Level": 9,
            "Pool ID": "POOL-0062",
            "Pool Internal Key": "kingsroad_bandits",
            "Status": "Planned",
            "Release Phase": "Launch",
            "Notes": "Hostile Kingsroad combat. No loot tables.",
        },
    )

    # Apothecary shop so steal can sit under the Shops tab.
    upsert(
        db["Shops"],
        "Shop ID",
        {
            "Shop ID": "SHP-0010",
            "Internal Key": "apothecary",
            "Display Name": "Apothecary",
            "Location ID": "LOC-0026",
            "NPC ID": None,
            "Status": "Planned",
            "Release Phase": "Launch",
            "Notes": "Buys potions and herbs. Unlocks with the Apothecary location.",
            "Entry 1 Item ID": "ITEM-0211",
            "Entry 1 Mode": "Sell",
            "Entry 1 Price": None,
            "Entry 1 Currency ID": "CUR-0001",
            "Entry 1 Daily Limit": None,
            "Entry 2 Item ID": "ITEM-0210",
            "Entry 2 Mode": "Sell",
            "Entry 2 Price": None,
            "Entry 2 Currency ID": "CUR-0001",
            "Entry 2 Daily Limit": None,
            "Entry 3 Item ID": "ITEM-0072",
            "Entry 3 Mode": "Sell",
            "Entry 3 Price": None,
            "Entry 3 Currency ID": "CUR-0001",
            "Entry 3 Daily Limit": None,
            "Entry 4 Item ID": "ITEM-0071",
            "Entry 4 Mode": "Sell",
            "Entry 4 Price": None,
            "Entry 4 Currency ID": "CUR-0001",
            "Entry 4 Daily Limit": None,
            "Entry 5 Item ID": "ITEM-0070",
            "Entry 5 Mode": "Sell",
            "Entry 5 Price": None,
            "Entry 5 Currency ID": "CUR-0001",
            "Entry 5 Daily Limit": None,
        },
    )

    # Keep enemy drop chance / gold at zero (already set).
    for eid in ("ENM-0026", "ENM-0029"):
        for enemy in db["Enemies"]:
            if enemy["Enemy ID"] == eid:
                enemy["Drop Chance"] = 0
                enemy["Reward Table ID"] = None
                enemy["Notes"] = (
                    "Kingsroad combat. No item drops."
                    if eid == "ENM-0026"
                    else "Kingsroad captain. No item drops."
                )

    DB_PATH.write_text(json.dumps(db, indent=2, ensure_ascii=False) + "\n")
    # Flutter bundled copy when present.
    flutter_db = ROOT / "app_flutter/content/data/game-database.json"
    if flutter_db.exists():
        flutter_db.write_text(DB_PATH.read_text())
    print("patched Kingsroad + Apothecary shop")
    print("  LOC-0052 Kingsroad @", KINGSROAD_X, KINGSROAD_Y)
    print("  ACT-0081 Fight the bandits POOL-0062 80/20")
    print("  SHP-0010 Apothecary at LOC-0026")


if __name__ == "__main__":
    main()
