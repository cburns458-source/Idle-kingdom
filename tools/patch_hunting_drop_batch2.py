#!/usr/bin/env python3
"""Hunting drop tables batch 2: flatten mains, tendons secondary, toad/spider legs."""
from __future__ import annotations

import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "content/data/game-database.json"
ASSETS = ROOT / "content/assets/icons/items"

VERSION = "2026-09-29-hunting-drops-batch2"
OLD_VERSIONS = (
    "2026-09-29-combat-drops-batch1",
    "2026-09-29-equipment-merge-enemy-mv",
)

TOAD_LEGS = "ITEM-0422"
SPIDER_LEGS = "ITEM-0423"
TENDONS = "ITEM-0044"
RWT_TENDONS = "RWT-0119"
RWT_HUNT_BOAR = "RWT-0191"
RWT_TOAD = "RWT-0192"
RWT_SPIDER = "RWT-0193"


def copy_icon(src_stem: str, dst_stem: str) -> None:
    src = ASSETS / f"item_{src_stem}.webp"
    dst = ASSETS / f"item_{dst_stem}.webp"
    if dst.exists():
        print(f"  icon exists {dst.name}")
        return
    if not src.exists():
        raise SystemExit(f"missing icon source {src}")
    shutil.copy2(src, dst)
    print(f"  icon {src.name} -> {dst.name}")


def upsert_item(items: list[dict], item_id: str, row: dict) -> None:
    existing = next((i for i in items if i.get("Item ID") == item_id), None)
    if existing:
        existing.update(row)
    else:
        items.append({"Item ID": item_id, **row})


def replace_table(
    rewards: list[dict],
    table_id: str,
    table_name: str,
    entries: list[tuple[str, str, int, int]],
    *,
    purpose: str = "Hunting item drops",
) -> None:
    rewards[:] = [e for e in rewards if e.get("Reward Table ID") != table_id]
    for entry_id, item_id, weight, qty in entries:
        rewards.append(
            {
                "Reward Entry ID": entry_id,
                "Reward Table ID": table_id,
                "Reward Table Name": table_name,
                "Purpose": purpose,
                "Reward Type": "Item",
                "Reward ID / Value": item_id,
                "Weight": weight,
                "Minimum Quantity": qty,
                "Maximum Quantity": qty,
                "Skill ID": None,
                "XP Amount": None,
                "Status": "Planned",
                "Notes": None,
            }
        )


def set_hunt(
    action: dict,
    *,
    drop_chance: float | int,
    reward_table: str,
    secondary_chance: float | int | None = None,
    secondary_table: str | None = None,
    notes: str | None = None,
) -> None:
    action["Drop Chance"] = drop_chance
    action["Reward Table ID"] = reward_table
    action["Secondary Drop Chance"] = secondary_chance
    action["Secondary Reward Table ID"] = secondary_table
    action["Tertiary Drop Chance"] = None
    action["Tertiary Reward Table ID"] = None
    if notes is not None:
        action["Notes"] = notes


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
    items = db["Items"]
    actions = {a["Action ID"]: a for a in db["Actions"]}
    rewards = db["RewardEntries"]

    copy_icon("raw_food", "toad_legs")
    copy_icon("bone_shard", "spider_legs")

    upsert_item(
        items,
        TOAD_LEGS,
        {
            "Internal Key": "toad_legs",
            "Display Name": "Toad Legs",
            "Category": "Resource",
            "Subtype": "Creature material",
            "Associated Skill ID": "SKL-0005",
            "Equipment Slot ID": None,
            "Functional / Source Tags": "hunting_output; giant_toad_drop",
            "Status": "Planned",
            "Release Phase": "Launch",
            "Description": "Meaty legs harvested from a giant toad.",
            "Icon Asset Key": "toad_legs",
            "Notes": "Placeholder art: raw food. Drop from Hunt giant toad.",
            "Base Sell Value": 95,
            "Stackable": None,
        },
    )
    upsert_item(
        items,
        SPIDER_LEGS,
        {
            "Internal Key": "spider_legs",
            "Display Name": "Spider Legs",
            "Category": "Resource",
            "Subtype": "Creature material",
            "Associated Skill ID": "SKL-0005",
            "Equipment Slot ID": None,
            "Functional / Source Tags": "hunting_output; giant_spider_drop",
            "Status": "Planned",
            "Release Phase": "Launch",
            "Description": "Jointed legs taken from a giant spider.",
            "Icon Asset Key": "spider_legs",
            "Notes": "Placeholder art: bone shard. Drop from Hunt giant spider.",
            "Base Sell Value": 120,
            "Stackable": None,
        },
    )

    # Ensure tendons secondary table is a clean singleton.
    replace_table(
        rewards,
        RWT_TENDONS,
        "Animal Tendons Secondary",
        [("RWE-0168", TENDONS, 100, 1)],
        purpose="Independent Hunting drop",
    )

    replace_table(
        rewards,
        "RWT-0049",
        "Weasel Drops",
        [("RWE-0091", "ITEM-0042", 100, 1)],  # Weasel Tail
    )
    replace_table(
        rewards,
        "RWT-0050",
        "Rabbit Drops",
        [
            ("RWE-0092", "ITEM-0052", 90, 1),  # Raw Rabbit
            ("RWE-0107", "ITEM-0038", 10, 1),  # Rabbit's Foot
        ],
    )
    replace_table(
        rewards,
        "RWT-0051",
        "Duck Drops",
        [("RWE-0093", "ITEM-0193", 100, 1)],  # Raw Duck
    )
    replace_table(
        rewards,
        "RWT-0052",
        "Pheasant Drops",
        [
            ("RWE-0094", "ITEM-0053", 90, 1),  # Raw Pheasant
            ("RWE-0108", "ITEM-0039", 10, 1),  # Pheasant Feathers
        ],
    )
    # Combat fight boar keeps RWT-0007 (60/30/10). Hunt boar gets its own table.
    replace_table(
        rewards,
        RWT_HUNT_BOAR,
        "Hunt Wild Boar Drops",
        [
            ("RWE-9218", "ITEM-0194", 70, 1),  # Raw Boar Meat
            ("RWE-9219", "ITEM-0195", 25, 1),  # Boar Hide
            ("RWE-9220", "ITEM-0043", 5, 1),  # Boar Tusk
        ],
    )
    replace_table(
        rewards,
        "RWT-0185",
        "Fox Drops",
        [("RWE-9209", "ITEM-0415", 100, 1)],  # Fox Tail
    )
    replace_table(
        rewards,
        "RWT-0053",
        "Elk Drops",
        [
            ("RWE-0095", "ITEM-0055", 45, 1),  # Venison
            ("RWE-0169", "ITEM-0379", 50, 1),  # Elk Hide
            ("RWE-0109", "ITEM-0041", 5, 1),  # Elk Horns
        ],
    )
    replace_table(
        rewards,
        "RWT-0123",
        "Sea Turtle Drops",
        [("RWE-0173", "ITEM-0348", 100, 1)],  # Raw Sea Turtle
    )
    replace_table(
        rewards,
        "RWT-0054",
        "Mountain Goat Drops",
        [("RWE-0096", "ITEM-0196", 100, 1)],  # Goat Hide
    )
    replace_table(
        rewards,
        "RWT-0055",
        "Great Stag Drops",
        [
            ("RWE-0097", "ITEM-0197", 95, 1),  # Great Stag Hide
            ("RWE-0110", "ITEM-0199", 5, 1),  # Great Antler
        ],
    )
    replace_table(
        rewards,
        RWT_TOAD,
        "Giant Toad Drops",
        [("RWE-9221", TOAD_LEGS, 100, 1)],
    )
    replace_table(
        rewards,
        RWT_SPIDER,
        "Giant Spider Drops",
        [("RWE-9222", SPIDER_LEGS, 100, 1)],
    )

    # Clear retired secondary-only tables that used to hold foot/feathers/horns/antler.
    for tid in ("RWT-0062", "RWT-0063", "RWT-0064", "RWT-0065"):
        rewards[:] = [e for e in rewards if e.get("Reward Table ID") != tid]

    tendons_note = "Animal Tendons secondary 5%."
    set_hunt(
        actions["ACN-0015"],
        drop_chance=40,
        reward_table="RWT-0049",
        notes="Weasel Tail 100% when the drop rolls (40% base). No tendons.",
    )
    set_hunt(
        actions["ACN-0016"],
        drop_chance=47.5,
        reward_table="RWT-0050",
        secondary_chance=5,
        secondary_table=RWT_TENDONS,
        notes=f"Raw Rabbit / Rabbit's Foot main. {tendons_note}",
    )
    set_hunt(
        actions["ACN-0013"],
        drop_chance=45,
        reward_table="RWT-0051",
        secondary_chance=5,
        secondary_table=RWT_TENDONS,
        notes=f"Raw Duck main. {tendons_note}",
    )
    set_hunt(
        actions["ACN-0017"],
        drop_chance=40,
        reward_table="RWT-0052",
        secondary_chance=5,
        secondary_table=RWT_TENDONS,
        notes=f"Raw Pheasant / Pheasant Feathers main. {tendons_note}",
    )
    set_hunt(
        actions["ACN-0204"],
        drop_chance=36,
        reward_table=RWT_HUNT_BOAR,
        notes="Hunt-only boar table (70/25/5). Combat boar keeps RWT-0007.",
    )
    set_hunt(
        actions["ACN-0205"],
        drop_chance=35,
        reward_table="RWT-0185",
        secondary_chance=5,
        secondary_table=RWT_TENDONS,
        notes=f"Fox Tail main (35% base). {tendons_note}",
    )
    set_hunt(
        actions["ACN-0014"],
        drop_chance=42.5,
        reward_table="RWT-0053",
        secondary_chance=5,
        secondary_table=RWT_TENDONS,
        notes=f"Venison / Elk Hide / Elk Horns main. {tendons_note}",
    )
    set_hunt(
        actions["ACN-0182"],
        drop_chance=50,
        reward_table="RWT-0123",
        notes="Raw Sea Turtle 100% when the drop rolls (50% base).",
    )
    set_hunt(
        actions["ACN-0112"],
        drop_chance=41,
        reward_table="RWT-0054",
        secondary_chance=5,
        secondary_table=RWT_TENDONS,
        notes=f"Goat Hide main. {tendons_note}",
    )
    set_hunt(
        actions["ACN-0113"],
        drop_chance=30,
        reward_table="RWT-0055",
        secondary_chance=5,
        secondary_table=RWT_TENDONS,
        notes=f"Great Stag Hide / Great Antler main. {tendons_note}",
    )
    set_hunt(
        actions["ACN-0206"],
        drop_chance=32,
        reward_table=RWT_TOAD,
        notes="Toad Legs 100% when the drop rolls (32% base).",
    )
    set_hunt(
        actions["ACN-0208"],
        drop_chance=28,
        reward_table=RWT_SPIDER,
        notes="Spider Legs 100% when the drop rolls (28% base).",
    )

    # Moonhorn elk unchanged structure except tendons stay tertiary→secondary if present.
    # Not in this batch; leave alone.

    db["RewardEntries"] = rewards
    DB_PATH.write_text(json.dumps(db, indent=2) + "\n")
    print(f"Wrote {DB_PATH}")

    bump_version(ROOT / "src/game/data/loadDatabase.ts")
    bump_version(ROOT / "packages/ik_content/lib/src/load_database.dart")


if __name__ == "__main__":
    main()
