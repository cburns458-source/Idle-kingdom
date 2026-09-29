#!/usr/bin/env python3
"""Thievery drop table updates (batch 3) + armory shop-tab routing tag."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "content/data/game-database.json"
VERSION = "2026-09-29-thievery-production-tabs"
OLD_VERSIONS = (
    "2026-09-29-hunting-drops-batch2",
    "2026-09-29-combat-drops-batch1",
    "2026-09-29-equipment-merge-enemy-mv",
)


def replace_table(
    rewards: list[dict],
    table_id: str,
    table_name: str,
    entries: list[dict],
) -> None:
    rewards[:] = [e for e in rewards if e.get("Reward Table ID") != table_id]
    for entry in entries:
        rewards.append(entry)


def item_entry(
    entry_id: str,
    table_id: str,
    table_name: str,
    item_id: str,
    weight: int,
    *,
    notes: str | None = None,
) -> dict:
    return {
        "Reward Entry ID": entry_id,
        "Reward Table ID": table_id,
        "Reward Table Name": table_name,
        "Purpose": "Primary output",
        "Reward Type": "Item",
        "Reward ID / Value": item_id,
        "Weight": weight,
        "Minimum Quantity": 1,
        "Maximum Quantity": 1,
        "Skill ID": None,
        "XP Amount": None,
        "Status": "Confirmed",
        "Notes": notes,
    }


def gold_entry(
    entry_id: str,
    table_id: str,
    table_name: str,
    amount: int,
    weight: int,
) -> dict:
    return {
        "Reward Entry ID": entry_id,
        "Reward Table ID": table_id,
        "Reward Table Name": table_name,
        "Purpose": "Primary output",
        "Reward Type": "Gold",
        "Reward ID / Value": str(amount),
        "Weight": weight,
        "Minimum Quantity": 1,
        "Maximum Quantity": 1,
        "Skill ID": None,
        "XP Amount": None,
        "Status": "Confirmed",
        "Notes": f"{amount} gold",
    }


def bump_version(path: Path) -> None:
    text = path.read_text()
    for old in OLD_VERSIONS:
        if old in text:
            path.write_text(text.replace(old, VERSION))
            print(f"  version {path.name}: {old} -> {VERSION}")
            return
    if VERSION in text:
        print(f"  version already {VERSION} in {path.name}")
        return
    raise SystemExit(f"could not bump version in {path}")


def main() -> None:
    db = json.loads(DB_PATH.read_text())
    actions = {a["Action ID"]: a for a in db["Actions"]}
    rewards = db["RewardEntries"]

    # Barracks → baked potato
    replace_table(
        rewards,
        "RWT-0126",
        "Barracks Steal",
        [
            item_entry(
                "RWE-T01260",
                "RWT-0126",
                "Barracks Steal",
                "ITEM-0058",
                100,
                notes="Baked potato",
            )
        ],
    )

    # Armory → iron helmet 10% / bronze helmet 90%; shop menu routing tag
    replace_table(
        rewards,
        "RWT-0172",
        "Armory Supply Chest",
        [
            item_entry(
                "RWE-T01720",
                "RWT-0172",
                "Armory Supply Chest",
                "ITEM-0155",
                10,
                notes="Iron helmet",
            ),
            item_entry(
                "RWE-T01721",
                "RWT-0172",
                "Armory Supply Chest",
                "ITEM-0228",
                90,
                notes="Bronze helmet",
            ),
        ],
    )
    armory = actions["ACN-0223"]
    notes = armory.get("Notes") or ""
    if "ThieveryShop" not in notes:
        armory["Notes"] = f"ThieveryShop; {notes}" if notes else "ThieveryShop"

    # Kitchen → perch / bass / venison
    replace_table(
        rewards,
        "RWT-0128",
        "Kitchen Steal",
        [
            item_entry("RWE-T01280", "RWT-0128", "Kitchen Steal", "ITEM-0059", 50, notes="Cooked perch"),
            item_entry("RWE-T01281", "RWT-0128", "Kitchen Steal", "ITEM-0062", 30, notes="Cooked bass"),
            item_entry("RWE-T01282", "RWT-0128", "Kitchen Steal", "ITEM-0067", 20, notes="Cooked venison"),
        ],
    )

    # Locked storeroom → elk horns / venison
    replace_table(
        rewards,
        "RWT-0176",
        "Locked Storeroom",
        [
            item_entry("RWE-T01760", "RWT-0176", "Locked Storeroom", "ITEM-0041", 50, notes="Elk horns"),
            item_entry("RWE-T01761", "RWT-0176", "Locked Storeroom", "ITEM-0055", 50, notes="Venison"),
        ],
    )

    # Noble purse → emerald
    replace_table(
        rewards,
        "RWT-0177",
        "Noble Purse",
        [
            gold_entry("RWE-T01770", "RWT-0177", "Noble Purse", 80, 70),
            item_entry("RWE-T01771", "RWT-0177", "Noble Purse", "ITEM-0013", 30, notes="Emerald"),
        ],
    )

    # Wizard shop → gold 150
    replace_table(
        rewards,
        "RWT-0178",
        "Wizard Shop Steal",
        [
            item_entry("RWE-T01781", "RWT-0178", "Wizard Shop Steal", "ITEM-0011", 60, notes="Essence"),
            gold_entry("RWE-T01780", "RWT-0178", "Wizard Shop Steal", 150, 40),
        ],
    )

    # Bank vault → gold 200 / ruby
    replace_table(
        rewards,
        "RWT-0179",
        "Bank Vault",
        [
            gold_entry("RWE-T01790", "RWT-0179", "Bank Vault", 200, 50),
            item_entry("RWE-T01791", "RWT-0179", "Bank Vault", "ITEM-0014", 50, notes="Ruby"),
        ],
    )

    db["RewardEntries"] = rewards
    DB_PATH.write_text(json.dumps(db, indent=2) + "\n")
    print(f"Wrote {DB_PATH}")
    bump_version(ROOT / "src/game/data/loadDatabase.ts")
    bump_version(ROOT / "packages/ik_content/lib/src/load_database.dart")


if __name__ == "__main__":
    main()
