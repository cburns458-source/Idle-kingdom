#!/usr/bin/env python3
"""Expand the Thievery ladder: convert goblin steal to a lockpick chest, add new
steal/pick actions (some unplaced), place Grand Bazaar / Apothecary / Wizard /
armory / castle Main Hall / Citadel Bank vault."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "content/data/game-database.json"

# Duration / XP interpolated from current thievery rows (L1–L64), extrapolated after.
def dur_xp(level: int) -> tuple[int, int]:
    rows = [
        (1, 12, 233),
        (10, 22, 426),
        (25, 38, 933),
        (30, 44, 1007),
        (45, 60, 1532),
        (50, 65, 2578),
        (64, 81, 3601),
    ]
    if level <= rows[0][0]:
        return rows[0][1], rows[0][2]
    if level >= rows[-1][0]:
        lo = rows[-2]
        hi = rows[-1]
        slope_d = (hi[1] - lo[1]) / (hi[0] - lo[0])
        slope_x = (hi[2] - lo[2]) / (hi[0] - lo[0])
        d = round(hi[1] + slope_d * (level - hi[0]))
        x = round(hi[2] + slope_x * (level - hi[0]))
        return d, x
    for i in range(len(rows) - 1):
        lo, hi = rows[i], rows[i + 1]
        if lo[0] <= level <= hi[0]:
            if lo[0] == hi[0]:
                return lo[1], lo[2]
            t = (level - lo[0]) / (hi[0] - lo[0])
            return round(lo[1] + t * (hi[1] - lo[1])), round(lo[2] + t * (hi[2] - lo[2]))
    return rows[-1][1], rows[-1][2]


def fail_chance(level: int) -> int:
    # Same stepped pattern as the live ladder (~+5 per tier).
    if level <= 10:
        return 35
    if level <= 25:
        return 40
    if level <= 35:
        return 40
    if level <= 45:
        return 45
    if level <= 55:
        return 50
    if level <= 70:
        return 55
    if level <= 85:
        return 60
    return 65


STEAL_ART = "actions/acn_steal_general_store.webp"
PICK_ART = "actions/acn_pick_safe.webp"
GOBLIN_ART = "actions/acn_steal_goblins.webp"
DEPOSIT_ART = "actions/acn_pick_deposit_box.webp"

# Placed + unplaced definitions.
# place=None means skill-menu / codex only (no Activity).
DEFS = [
    {
        "id": "ACN-0223",
        "key": "pick_armory_supply_chest",
        "name": "Pick the armory supply chest",
        "level": 20,
        "kind": "pick",
        "art": PICK_ART,
        "table": "RWT-0172",
        "table_name": "Armory Supply Chest",
        "rewards": [
            ("Gold", "15", 50, "15 gold"),
            ("Item", "ITEM-0368", 50, "Copper dagger"),
        ],
        "act": "ACT-0071",
        "pool": "POOL-0053",
        "pen": "PEN-0111",
        "loc": "LOC-0032",
        "desc": "Crack the Combat Training Grounds armory chest. Needs lockpicks.",
    },
    {
        "id": "ACN-0190",
        "key": "pick_goblin_camp_chest",
        "name": "Pick the Goblin Camp chest",
        "level": 25,
        "kind": "pick",
        "art": GOBLIN_ART,
        "table": "RWT-0153",
        "table_name": "Goblin Camp Chest",
        "rewards": [
            ("Item", "ITEM-0048", 50, "Raw trout"),
            ("Gold", "5", 50, "5 gold"),
        ],
        "act": "ACT-0058",
        "pool": "POOL-0046",
        "pen": "PEN-0100",
        "loc": "LOC-0003",
        "desc": "Pick the locked goblin chest for trout or a few coins. Needs lockpicks.",
        "convert": True,
    },
    {
        "id": "ACN-0224",
        "key": "pick_merchants_chest",
        "name": "Pick a merchant's chest",
        "level": 35,
        "kind": "pick",
        "art": PICK_ART,
        "table": "RWT-0173",
        "table_name": "Merchant Chest",
        "rewards": [
            ("Gold", "25", 60, "25 gold"),
            ("Item", "ITEM-0006", 40, "Coal"),
        ],
        "place": None,
        "desc": "Crack a traveling merchant's locked chest. Needs lockpicks.",
    },
    {
        "id": "ACN-0225",
        "key": "steal_grand_bazaar",
        "name": "Steal from the Grand Bazaar",
        "level": 40,
        "kind": "steal",
        "art": STEAL_ART,
        "table": "RWT-0174",
        "table_name": "Grand Bazaar Steal",
        "rewards": [
            ("Gold", "30", 50, "30 gold"),
            ("Item", "ITEM-0025", 50, "Potato"),
        ],
        "act": "ACT-0072",
        "pool": "POOL-0054",
        "pen": "PEN-0112",
        "loc": "LOC-0029",
        "desc": "Lift goods from a Grand Bazaar stall when the keeper looks away.",
    },
    {
        "id": "ACN-0226",
        "key": "steal_apothecary",
        "name": "Steal from the Apothecary",
        "level": 50,
        "kind": "steal",
        "art": STEAL_ART,
        "table": "RWT-0175",
        "table_name": "Apothecary Steal",
        "rewards": [
            ("Gold", "40", 40, "40 gold"),
            ("Item", "ITEM-0070", 60, "Luck potion"),
        ],
        "act": "ACT-0073",
        "pool": "POOL-0055",
        "pen": "PEN-0113",
        "loc": "LOC-0026",
        "desc": "Slip a vial from Rose's shelves when she is busy with a customer.",
    },
    {
        "id": "ACN-0227",
        "key": "pick_locked_storeroom",
        "name": "Pick a locked storeroom",
        "level": 65,
        "kind": "pick",
        "art": PICK_ART,
        "table": "RWT-0176",
        "table_name": "Locked Storeroom",
        "rewards": [
            ("Gold", "60", 50, "60 gold"),
            ("Item", "ITEM-0005", 50, "Iron ore"),
        ],
        "place": None,
        "desc": "Open a heavy storeroom lock. Needs lockpicks.",
    },
    {
        "id": "ACN-0228",
        "key": "steal_nobles_purse",
        "name": "Steal from a noble's purse",
        "level": 70,
        "kind": "steal",
        "art": STEAL_ART,
        "table": "RWT-0177",
        "table_name": "Noble Purse",
        "rewards": [
            ("Gold", "80", 70, "80 gold"),
            ("Item", "ITEM-0012", 30, "Sapphire"),
        ],
        "act": "ACT-0074",
        "pool": "POOL-0056",
        "pen": "PEN-0114",
        "loc": "LOC-0015",
        "desc": "Cut a purse in the castle Main Hall while the court is distracted.",
    },
    {
        "id": "ACN-0229",
        "key": "steal_wizards_shop",
        "name": "Steal from the Wizard's Shop",
        "level": 80,
        "kind": "steal",
        "art": STEAL_ART,
        "table": "RWT-0178",
        "table_name": "Wizard Shop Steal",
        "rewards": [
            ("Gold", "100", 40, "100 gold"),
            ("Item", "ITEM-0011", 60, "Essence"),
        ],
        "act": "ACT-0075",
        "pool": "POOL-0057",
        "pen": "PEN-0115",
        "loc": "LOC-0007",
        "desc": "Pinch wares from the Wizard's Tower shop when the mage turns away.",
    },
    {
        "id": "ACN-0230",
        "key": "pick_bank_vault",
        "name": "Pick the bank vault",
        "level": 90,
        "kind": "pick",
        "art": DEPOSIT_ART,
        "table": "RWT-0179",
        "table_name": "Bank Vault",
        "rewards": [
            ("Gold", "150", 50, "150 gold"),
            ("Item", "ITEM-0010", 50, "Tungsten ore"),
        ],
        "act": "ACT-0076",
        "pool": "POOL-0058",
        "pen": "PEN-0116",
        "loc": "LOC-0035",
        "desc": "Crack the Citadel Bank vault. Needs lockpicks.",
        "bank": True,
    },
]


def notes_for(defn: dict) -> str:
    fc = fail_chance(defn["level"])
    if defn["kind"] == "pick":
        base = f"ThieveryLockpick; RequiresLockpick; FailChance:{fc}; FailDamagePercent:10"
        if defn.get("bank"):
            return base + "; BankThievery"
        return base
    return f"ThieverySteal; FailChance:{fc}; FailDamagePercent:10"


def upsert_action(db: dict, defn: dict) -> None:
    duration, xp = dur_xp(defn["level"])
    row = {
        "Action ID": defn["id"],
        "Internal Key": defn["key"],
        "Display Name": defn["name"],
        "Category": "Gathering",
        "Relevant Skill ID": "SKL-0015",
        "Target Type": None,
        "Target ID": None,
        "Proficiency Level": defn["level"],
        "Base Duration Seconds": duration,
        "XP Reward": xp,
        "Guaranteed Gold": 0,
        "Drop Chance": 50,
        "Reward Table ID": defn["table"],
        "Secondary Drop Chance": None,
        "Secondary Reward Table ID": None,
        "Status": "Confirmed",
        "Release Phase": "Launch",
        "Notes": notes_for(defn),
        "Sprite Asset Key": defn["art"],
    }
    existing = next((a for a in db["Actions"] if a["Action ID"] == defn["id"]), None)
    if existing:
        existing.update(row)
    else:
        db["Actions"].append(row)


def upsert_place(db: dict, defn: dict) -> None:
    if defn.get("place") is None and "act" not in defn:
        return
    activity = {
        "Activity ID": defn["act"],
        "Internal Key": defn["key"],
        "Contextual Name": defn["name"],
        "Location ID": defn["loc"],
        "Description": defn["desc"],
        "Danger Warning Combat Level": None,
        "Pool ID": defn["pool"],
        "Pool Internal Key": defn["key"],
        "Status": "Confirmed",
        "Release Phase": "Launch",
        "Notes": None,
    }
    existing = next((a for a in db["Activities"] if a["Activity ID"] == defn["act"]), None)
    if existing:
        existing.update(activity)
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


def upsert_rewards(db: dict, defn: dict) -> None:
    rewards = db["RewardEntries"]
    keep = [e for e in rewards if e.get("Reward Table ID") != defn["table"]]
    rewards[:] = keep
    suffix = defn["table"].split("-")[1]
    for i, (rtype, rid, weight, note) in enumerate(defn["rewards"]):
        rewards.append(
            {
                "Reward Entry ID": f"RWE-T{suffix}{i}",
                "Reward Table ID": defn["table"],
                "Reward Table Name": defn["table_name"],
                "Purpose": "Primary output",
                "Reward Type": rtype,
                "Reward ID / Value": rid,
                "Weight": weight,
                "Minimum Quantity": 1,
                "Maximum Quantity": 1,
                "Skill ID": None,
                "XP Amount": None,
                "Status": "Confirmed",
                "Notes": note,
            }
        )


def validate_items(db: dict) -> None:
    ids = {i["Item ID"] for i in db["Items"]}
    for defn in DEFS:
        for rtype, rid, _, _ in defn["rewards"]:
            if rtype == "Item" and rid not in ids:
                raise SystemExit(f"missing item {rid} for {defn['id']}")


def main() -> None:
    db = json.loads(DB_PATH.read_text())
    validate_items(db)

    for defn in DEFS:
        upsert_action(db, defn)
        upsert_rewards(db, defn)
        if defn.get("place") is not None or "act" in defn:
            # place=None explicitly skips; convert/goblin and new placed have act.
            if defn.get("place") is None and not defn.get("convert") and "loc" not in defn:
                continue
            if defn.get("place") is None and "loc" not in defn:
                continue
            if "loc" in defn:
                upsert_place(db, defn)

    text = json.dumps(db, indent=2, ensure_ascii=False) + "\n"
    DB_PATH.write_text(text)
    mirror = ROOT / "app_flutter/content/data/game-database.json"
    if mirror.exists() and mirror.resolve() != DB_PATH.resolve():
        mirror.write_text(text)
    print("patched thievery ladder:")
    for defn in DEFS:
        d, x = dur_xp(defn["level"])
        where = defn.get("loc") or "unplaced"
        print(
            f"  L{defn['level']:>2} {defn['id']} {defn['name']} "
            f"({d}s {x}xp fail {fail_chance(defn['level'])}) @ {where}"
        )


if __name__ == "__main__":
    main()
