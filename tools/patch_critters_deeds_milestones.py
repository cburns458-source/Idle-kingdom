#!/usr/bin/env python3
"""Critters, Champion deeds, project milestones content patch."""
from __future__ import annotations

import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "content/data/game-database.json"
CRITTER_DIR = ROOT / "content/assets/critters"
PET_ICON_DIR = ROOT / "content/assets/icons/items"

CRITTERS = [
    # Replace fly in place
    {
        "id": "CRT-0001",
        "key": "chick",
        "name": "Chick",
        "loc": "LOC-0001",
        "desc": "A fluffy farmyard hatchling.",
        "pet_item": "ITEM-0320",
        "pet_cos": "COS-0004",
        "pet_desc": "A fluffy companion found on the farm.",
        "replace": True,
    },
    {
        "id": "CRT-0005",
        "key": "squirrel",
        "name": "Squirrel",
        "loc": "LOC-0008",
        "desc": "A quick nut-hoarder of the Kingswoods.",
        "pet_item": "ITEM-0400",
        "pet_cos": "COS-0008",
        "pet_desc": "A quick companion found in the Kingswoods.",
    },
    {
        "id": "CRT-0006",
        "key": "crab",
        "name": "Crab",
        "loc": "LOC-0043",
        "desc": "A sideways scavenger of the shallows.",
        "pet_item": "ITEM-0401",
        "pet_cos": "COS-0009",
        "pet_desc": "A sideways companion found in the shallows.",
    },
    {
        "id": "CRT-0007",
        "key": "pika",
        "name": "Pika",
        "loc": "LOC-0046",
        "desc": "A tiny haymaker of the slopes.",
        "pet_item": "ITEM-0402",
        "pet_cos": "COS-0010",
        "pet_desc": "A tiny companion found on the slopes.",
    },
    {
        "id": "CRT-0008",
        "key": "raccoon",
        "name": "Raccoon",
        "loc": "LOC-0030",
        "desc": "A masked bandit of the Processing District.",
        "pet_item": "ITEM-0403",
        "pet_cos": "COS-0011",
        "pet_desc": "A masked companion found in the Processing District.",
    },
    {
        "id": "CRT-0009",
        "key": "baby_dragon",
        "name": "Baby Dragon",
        "loc": "",  # combat secondary only — no habitat hour-roll
        "desc": "A rare hatchling that sometimes follows a dragon's defeat.",
        "pet_item": "ITEM-0404",
        "pet_cos": "COS-0012",
        "pet_desc": "A rare companion that hatches after a dragon falls.",
    },
]

# Deeds: ACH-0015 removed (becomes milestone). Move dragon/ent to Champion.
# Dark nights stays on Hard. New rows ACH-0040+.
NEW_DEEDS = [
    {
        "Achievement ID": "ACH-0040",
        "Internal Key": "turnip_for_what",
        "Display Name": "Turnip for what",
        "Category": "Milestones",
        "Difficulty": "Easy",
        "Check Type": "botany_harvest",
        "Target ID": "ITEM-0370@LOC-0001",
        "Required Count": 1,
        "Required Level": None,
        "Status": "Planned",
        "Release Phase": "Launch",
        "Reward": None,
        "Target Skill ID": None,
        "Notes": "Harvest a turnip plant at the farm patch.",
    },
    {
        "Achievement ID": "ACH-0041",
        "Internal Key": "market_rate",
        "Display Name": "Market rate",
        "Category": "Milestones",
        "Difficulty": "Medium",
        "Check Type": "thievery_success",
        "Target ID": "ACN-0225",
        "Required Count": 1,
        "Required Level": None,
        "Status": "Planned",
        "Release Phase": "Launch",
        "Reward": None,
        "Target Skill ID": None,
        "Notes": "Steal from the Grand Bazaar.",
    },
    {
        "Achievement ID": "ACH-0042",
        "Internal Key": "jaws",
        "Display Name": "Jaws",
        "Category": "Milestones",
        "Difficulty": "Hard",
        "Check Type": "gather_wield_tag",
        "Target ID": "ITEM-0051+wield_tag:fishing_tool",
        "Required Count": 1,
        "Required Level": None,
        "Status": "Planned",
        "Release Phase": "Launch",
        "Reward": None,
        "Target Skill ID": None,
        "Notes": "Catch a shark with a fishing rod.",
    },
    {
        "Achievement ID": "ACH-0043",
        "Internal Key": "vampire",
        "Display Name": "Vampire",
        "Category": "Milestones",
        "Difficulty": "Hard",
        "Check Type": "lifesteal_round",
        "Target ID": None,
        "Required Count": 100,
        "Required Level": None,
        "Status": "Planned",
        "Release Phase": "Launch",
        "Reward": None,
        "Target Skill ID": None,
        "Notes": "Heal 100 or more HP with lifesteal in a single combat round.",
    },
    {
        "Achievement ID": "ACH-0044",
        "Internal Key": "blood_gem",
        "Display Name": "Blood gem",
        "Category": "Milestones",
        "Difficulty": "Hard",
        "Check Type": "output_at_location",
        "Target ID": "ITEM-0090@LOC-0030",
        "Required Count": 1,
        "Required Level": None,
        "Status": "Planned",
        "Release Phase": "Launch",
        "Reward": None,
        "Target Skill ID": None,
        "Notes": "Cut a ruby in the Processing District.",
    },
    {
        "Achievement ID": "ACH-0045",
        "Internal Key": "moonlit_trophy",
        "Display Name": "Moonlit trophy",
        "Category": "Milestones",
        "Difficulty": "Hard",
        "Check Type": "gather_drop",
        "Target ID": "ITEM-0197@LOC-0044+wield:*",
        "Required Count": 1,
        "Required Level": None,
        "Status": "Planned",
        "Release Phase": "Launch",
        "Reward": None,
        "Target Skill ID": None,
        "Notes": "Hunt the great stag in the Starlight Glade.",
    },
    {
        "Achievement ID": "ACH-0046",
        "Internal Key": "tall_timber",
        "Display Name": "Tall timber",
        "Category": "Milestones",
        "Difficulty": "Hard",
        "Check Type": "botany_harvest",
        "Target ID": "ITEM-0019@LOC-0009",
        "Required Count": 1,
        "Required Level": None,
        "Status": "Planned",
        "Release Phase": "Launch",
        "Reward": None,
        "Target Skill ID": None,
        "Notes": "Grow a mahogany tree in the Meadow.",
    },
    {
        "Achievement ID": "ACH-0047",
        "Internal Key": "ember_harvest",
        "Display Name": "Ember harvest",
        "Category": "Milestones",
        "Difficulty": "Champion",
        "Check Type": "botany_harvest",
        "Target ID": "ITEM-0376@*",
        "Required Count": 1,
        "Required Level": None,
        "Status": "Planned",
        "Release Phase": "Launch",
        "Reward": None,
        "Target Skill ID": None,
        "Notes": "Harvest an emberblossom plant.",
    },
    {
        "Achievement ID": "ACH-0048",
        "Internal Key": "super_speed",
        "Display Name": "Super speed",
        "Category": "Milestones",
        "Difficulty": "Champion",
        "Check Type": "equip_count",
        "Target ID": "ITEM-0398",
        "Required Count": 4,
        "Required Level": None,
        "Status": "Planned",
        "Release Phase": "Launch",
        "Reward": None,
        "Target Skill ID": None,
        "Notes": "Equip four Haste spells.",
    },
    {
        "Achievement ID": "ACH-0049",
        "Internal Key": "bleeding_tooth",
        "Display Name": "Bleeding tooth",
        "Category": "Milestones",
        "Difficulty": "Champion",
        "Check Type": "gather_drop",
        "Target ID": "ITEM-0388@LOC-0000+wield:none",
        "Required Count": 1,
        "Required Level": None,
        "Status": "Planned",
        "Release Phase": "Launch",
        "Reward": None,
        "Target Skill ID": None,
        "Notes": "Harvest bleeding tooth. Action is unplaced — incomplete until placed.",
    },
]


def upsert_item(db: dict, item: dict) -> None:
    existing = next((i for i in db["Items"] if i["Item ID"] == item["Item ID"]), None)
    if existing:
        existing.update(item)
    else:
        db["Items"].append(item)


def upsert_cosmetic(db: dict, row: dict) -> None:
    existing = next((c for c in db["Cosmetics"] if c["Cosmetic ID"] == row["Cosmetic ID"]), None)
    if existing:
        existing.update(row)
    else:
        db["Cosmetics"].append(row)


def copy_placeholder(key: str) -> None:
    src_crt = CRITTER_DIR / "crt_fly.webp"
    src_pet = PET_ICON_DIR / "item_cosmetic_pet_fly.webp"
    dst_crt = CRITTER_DIR / f"crt_{key}.webp"
    dst_pet = PET_ICON_DIR / f"item_cosmetic_pet_{key}.webp"
    if src_crt.exists() and not dst_crt.exists():
        shutil.copy2(src_crt, dst_crt)
    if key == "chick" and src_crt.exists():
        # Replace fly art path with chick name; keep old fly file for safety.
        shutil.copy2(src_crt, dst_crt)
    if src_pet.exists():
        shutil.copy2(src_pet, dst_pet)


def main() -> None:
    db = json.loads(DB_PATH.read_text())

    for critter in CRITTERS:
        copy_placeholder(critter["key"])
        upsert_item(
            db,
            {
                "Item ID": critter["pet_item"],
                "Internal Key": f"cosmetic_pet_{critter['key']}",
                "Display Name": f"{critter['name']} Pet",
                "Category": "Cosmetic",
                "Subtype": "Pet",
                "Status": "Confirmed",
                "Release Phase": "Launch",
                "Associated Skill ID": None,
                "Equipment Slot ID": None,
                "Base Sell Value": 0,
                "Icon Asset Key": f"cosmetic_pet_{critter['key']}",
                "Description": critter["pet_desc"],
                "Functional / Source Tags": "cosmetic; pet; critter",
                "Notes": f"Unlocked the first time Critter {critter['id']} is collected.",
                "Stackable": None,
            },
        )
        upsert_cosmetic(
            db,
            {
                "Cosmetic ID": critter["pet_cos"],
                "Item ID": critter["pet_item"],
                "Cosmetic Slot ID": "CSLOT-0002",
                "Acquisition Tags": "critter",
                "Status": "Confirmed",
                "Release Phase": "Launch",
                "Notes": f"Pet form of {critter['id']}. Granted on first collection.",
            },
        )

    # Dragon secondary: Baby Dragon critter grant
    for a in db["Actions"]:
        if a["Action ID"] == "ACN-0092":
            a["Secondary Drop Chance"] = 5
            a["Secondary Reward Table ID"] = "RWT-0180"
            break
    db["RewardEntries"] = [
        e for e in db["RewardEntries"] if e.get("Reward Table ID") != "RWT-0180"
    ]
    db["RewardEntries"].append(
        {
            "Reward Entry ID": "RWE-T01800",
            "Reward Table ID": "RWT-0180",
            "Reward Table Name": "Baby Dragon",
            "Purpose": "Secondary output",
            "Reward Type": "Critter",
            "Reward ID / Value": "CRT-0009",
            "Weight": 100,
            "Minimum Quantity": 1,
            "Maximum Quantity": 1,
            "Skill ID": None,
            "XP Amount": None,
            "Status": "Confirmed",
            "Notes": "Grants Baby Dragon to the critter collection.",
        }
    )

    # Achievements: remove critter collector deed; retier dragon/ent; add new
    achievements = [
        a for a in db["Achievements"] if a["Achievement ID"] != "ACH-0015"
    ]
    for a in achievements:
        if a["Achievement ID"] in {"ACH-0038", "ACH-0039"}:
            a["Difficulty"] = "Champion"
    by_id = {a["Achievement ID"]: a for a in achievements}
    for deed in NEW_DEEDS:
        if deed["Achievement ID"] in by_id:
            by_id[deed["Achievement ID"]].update(deed)
        else:
            achievements.append(deed)
    db["Achievements"] = achievements

    text = json.dumps(db, indent=2, ensure_ascii=False) + "\n"
    DB_PATH.write_text(text)
    mirror = ROOT / "app_flutter/content/data/game-database.json"
    if mirror.exists() and mirror.resolve() != DB_PATH.resolve():
        mirror.write_text(text)

    print("patched critters/deeds content")
    print("  critters:", ", ".join(c["key"] for c in CRITTERS))
    print("  deeds:", len(NEW_DEEDS), "new;", "ACH-0015 removed; dragon/ent → Champion")


if __name__ == "__main__":
    main()
