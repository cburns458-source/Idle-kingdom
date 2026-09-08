#!/usr/bin/env python3
"""Add L64 Steal from the mining merchant (1× coal) at LOC-0012."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "content/data/game-database.json"

# Shop steal: ~2× gathering duration near L60–65, XP/hr ≈ interpolated gathering
# (tungsten L60 150k xp/hr @ 300s; shark L65 164k @ 330s → L64 ~160k).
# Duration 640s ≈ 2 × 320s mid gather; XP 28,450 → ~159,844 xp/hr.
ACTION = {
    "id": "ACN-0192",
    "key": "steal_mining_merchant",
    "name": "Steal from the mining merchant",
    "level": 64,
    "duration": 640,
    "xp": 28450,
    "notes": "ThieverySteal; FailChance:55; FailDamagePercent:10",
    "table": "RWT-0155",
    "act": "ACT-0061",
    "pool": "POOL-0048",
    "pen": "PEN-0102",
    "loc": "LOC-0012",
    "ctx": "Steal from the mining merchant",
    "desc": "Slip a lump of coal from the Dwarven Mining Store shelves.",
}


def main() -> None:
    db = json.loads(DB_PATH.read_text())
    actions = {a["Action ID"]: a for a in db["Actions"]}
    defn = ACTION

    row = {
        "Action ID": defn["id"],
        "Internal Key": defn["key"],
        "Display Name": defn["name"],
        "Category": "Gathering",
        "Relevant Skill ID": "SKL-0015",
        "Target Type": None,
        "Target ID": None,
        "Proficiency Level": defn["level"],
        "Base Duration Seconds": defn["duration"],
        "XP Reward": defn["xp"],
        "Guaranteed Gold": 0,
        "Drop Chance": 100,
        "Reward Table ID": defn["table"],
        "Secondary Drop Chance": None,
        "Secondary Reward Table ID": None,
        "Status": "Confirmed",
        "Release Phase": "Launch",
        "Notes": defn["notes"],
    }
    if defn["id"] in actions:
        actions[defn["id"]].update(row)
    else:
        db["Actions"].append(row)

    activity = {
        "Activity ID": defn["act"],
        "Internal Key": defn["key"],
        "Contextual Name": defn["ctx"],
        "Location ID": defn["loc"],
        "Description": defn["desc"],
        "Danger Warning Combat Level": None,
        "Pool ID": defn["pool"],
        "Pool Internal Key": defn["key"],
        "Status": "Confirmed",
        "Release Phase": "Launch",
        "Notes": None,
    }
    existing_act = next((a for a in db["Activities"] if a["Activity ID"] == defn["act"]), None)
    if existing_act:
        existing_act.update(activity)
    else:
        db["Activities"].append(activity)

    pool_entry = {
        "Pool Entry ID": defn["pen"],
        "Pool ID": defn["pool"],
        "Action ID": defn["id"],
        "Weight": 100,
        "Status": "Confirmed",
        "Notes": None,
    }
    existing_pen = next(
        (p for p in db["PoolEntries"] if p["Pool Entry ID"] == defn["pen"]), None
    )
    if existing_pen:
        existing_pen.update(pool_entry)
    else:
        db["PoolEntries"].append(pool_entry)

    rewards = db["RewardEntries"]
    keep = [e for e in rewards if e.get("Reward Table ID") != defn["table"]]
    rewards[:] = keep
    rewards.append(
        {
            "Reward Entry ID": f"RWE-T{defn['table'][-4:]}0",
            "Reward Table ID": defn["table"],
            "Reward Table Name": "Mining Merchant Steal",
            "Purpose": "Primary output",
            "Reward Type": "Item",
            "Reward ID / Value": "ITEM-0006",
            "Weight": 100,
            "Minimum Quantity": 1,
            "Maximum Quantity": 1,
            "Skill ID": None,
            "XP Amount": None,
            "Status": "Confirmed",
            "Notes": "Guaranteed 1 coal",
        }
    )

    DB_PATH.write_text(json.dumps(db, separators=(",", ":"), ensure_ascii=False) + "\n")
    mirror = ROOT / "app_flutter/content/data/game-database.json"
    if mirror.exists() and mirror.resolve() != DB_PATH.resolve():
        mirror.write_text(DB_PATH.read_text())
    print(
        f"patched {defn['id']}: {defn['duration']}s {defn['xp']}xp "
        f"({defn['xp'] / defn['duration'] * 3600:.0f} xp/hr) at {defn['loc']}"
    )


if __name__ == "__main__":
    main()
