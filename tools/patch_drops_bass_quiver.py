#!/usr/bin/env python3
"""Willow/yew/cinnamon drops, tuna→bass rename, icon renames for content DB."""
from __future__ import annotations

import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "content/data/game-database.json"
ASSETS = ROOT / "content/assets"


def rename_asset(old_rel: str, new_rel: str) -> None:
    old = ASSETS / old_rel
    new = ASSETS / new_rel
    if old.exists() and not new.exists():
        shutil.copy2(old, new)
        print(f"  asset {old_rel} -> {new_rel}")
    elif new.exists():
        print(f"  asset exists {new_rel}")
    else:
        print(f"  WARN missing {old_rel}")


def upsert_reward(entries: list[dict], entry_id: str, row: dict) -> None:
    existing = next((e for e in entries if e.get("Reward Entry ID") == entry_id), None)
    if existing:
        existing.update(row)
    else:
        entries.append(row)


def main() -> None:
    db = json.loads(DB_PATH.read_text())
    items = {i["Item ID"]: i for i in db["Items"]}
    actions = {a["Action ID"]: a for a in db["Actions"]}
    rewards = db["RewardEntries"]

    # --- Named byproducts (reuse generic branch/bark + elder yew IDs) ---
    items["ITEM-0386"].update(
        {
            "Internal Key": "willow_branches",
            "Display Name": "Willow Branches",
            "Icon Asset Key": "willow_branches",
            "Description": "Supple willow branches cut from the tree.",
            "Notes": "Primary willow woodcutting drop.",
        }
    )
    items["ITEM-0387"].update(
        {
            "Internal Key": "cinnamon_bark",
            "Display Name": "Cinnamon Bark",
            "Icon Asset Key": "cinnamon_bark",
            "Description": "Fragrant bark stripped from a cinnamon tree.",
            "Notes": "Primary cinnamon woodcutting drop.",
        }
    )
    items["ITEM-0219"].update(
        {
            "Internal Key": "yew_branches",
            "Display Name": "Yew Branches",
            "Icon Asset Key": "yew_branches",
            "Subtype": "Wood byproduct",
            "Functional / Source Tags": "woodcutting_output; crafting_output; smithing_input; artisanry_input",
            "Description": "Tough yew branches used in ancient crafts.",
            "Notes": "Primary elder-yew woodcutting drop; replaces former Elder Yew timber.",
        }
    )
    # Logs no longer drop; keep rows for old saves / retirement.
    items["ITEM-0383"]["Notes"] = "Retired gather drop; willow trees drop Willow Branches."
    items["ITEM-0384"]["Notes"] = "Retired gather drop; cinnamon trees drop Cinnamon Bark."

    # Saplings: willow yields branches; elder yew yields yew branches.
    items["ITEM-0410"]["Notes"] = (
        "BotanyPlant; Output:ITEM-0386; GrowSeconds:43200; Xp:28000; RequiresLevel:41"
    )
    items["ITEM-0412"]["Notes"] = (
        "BotanyPlant; Output:ITEM-0219; GrowSeconds:43200; Xp:200000; RequiresLevel:91"
    )

    rename_asset("icons/items/item_branches.webp", "icons/items/item_willow_branches.webp")
    rename_asset("icons/items/item_bark.webp", "icons/items/item_cinnamon_bark.webp")
    rename_asset("icons/items/item_elder_yew.webp", "icons/items/item_yew_branches.webp")

    # Primary reward tables → byproducts
    for e in rewards:
        if e["Reward Table ID"] == "RWT-0157":
            e["Reward ID / Value"] = "ITEM-0386"
            e["Reward Table Name"] = "Willow Branches Main Reward"
        if e["Reward Table ID"] == "RWT-0159":
            e["Reward ID / Value"] = "ITEM-0387"
            e["Reward Table Name"] = "Cinnamon Bark Main Reward"
        if e["Reward Table ID"] == "RWT-0034":
            e["Reward Table Name"] = "Yew Branches Main Reward"

    # Sapling secondaries (0.5%), matching other trees.
    upsert_reward(
        rewards,
        "RWE-9206",
        {
            "Reward Entry ID": "RWE-9206",
            "Reward Table ID": "RWT-0182",
            "Reward Table Name": "Botany sapling ITEM-0410",
            "Purpose": "Botany seed tertiary",
            "Reward Type": "Item",
            "Reward ID / Value": "ITEM-0410",
            "Weight": 100,
            "Minimum Quantity": 1,
            "Maximum Quantity": 1,
            "Skill ID": None,
            "XP Amount": None,
            "Status": "Planned",
            "Notes": "Willow sapling secondary.",
        },
    )
    upsert_reward(
        rewards,
        "RWE-9207",
        {
            "Reward Entry ID": "RWE-9207",
            "Reward Table ID": "RWT-0183",
            "Reward Table Name": "Botany sapling ITEM-0411",
            "Purpose": "Botany seed tertiary",
            "Reward Type": "Item",
            "Reward ID / Value": "ITEM-0411",
            "Weight": 100,
            "Minimum Quantity": 1,
            "Maximum Quantity": 1,
            "Skill ID": None,
            "XP Amount": None,
            "Status": "Planned",
            "Notes": "Ironwood sapling secondary.",
        },
    )
    upsert_reward(
        rewards,
        "RWE-9208",
        {
            "Reward Entry ID": "RWE-9208",
            "Reward Table ID": "RWT-0184",
            "Reward Table Name": "Botany sapling ITEM-0412",
            "Purpose": "Botany seed tertiary",
            "Reward Type": "Item",
            "Reward ID / Value": "ITEM-0412",
            "Weight": 100,
            "Minimum Quantity": 1,
            "Maximum Quantity": 1,
            "Skill ID": None,
            "XP Amount": None,
            "Status": "Planned",
            "Notes": "Elder yew sapling secondary.",
        },
    )

    # Actions: keep primary chances; swap secondaries to saplings (or clear cinnamon).
    actions["ACN-0200"].update(
        {
            "Target ID": "ITEM-0386",
            "Secondary Drop Chance": 0.5,
            "Secondary Reward Table ID": "RWT-0182",
            "Notes": "Primary Willow Branches. Sapling secondary 0.5%.",
        }
    )
    actions["ACN-0201"].update(
        {
            "Target ID": "ITEM-0387",
            "Secondary Drop Chance": None,
            "Secondary Reward Table ID": None,
            "Notes": "Primary Cinnamon Bark only. No generic bark secondary.",
        }
    )
    actions["ACN-0202"].update(
        {
            "Secondary Drop Chance": 0.5,
            "Secondary Reward Table ID": "RWT-0183",
            "Notes": "Primary Ironwood Log. Sapling secondary 0.5%. No bark.",
        }
    )
    actions["ACN-0051"].update(
        {
            "Display Name": "Cut elder yew",
            "Target ID": "ITEM-0219",
            "Secondary Drop Chance": 0.5,
            "Secondary Reward Table ID": "RWT-0184",
            "Notes": "Primary Yew Branches. Sapling secondary 0.5%.",
        }
    )

    # Production craft that made Elder Yew timber now makes Yew Branches.
    for a in db["Actions"]:
        if a.get("Action ID") == "ACN-0146":
            a["Display Name"] = "Yew Branches"
            a["Internal Key"] = "craft_yew_branches"
            a["Target ID"] = "ITEM-0219"
    for r in db["Recipes"]:
        if r.get("Recipe ID") == "RCP-0052":
            r["Display Name"] = "Yew Branches"
            r["Internal Key"] = "craft_yew_branches"

    # --- Tuna → Bass (everything) ---
    items["ITEM-0050"].update(
        {
            "Internal Key": "raw_bass",
            "Display Name": "Raw Bass",
            "Icon Asset Key": "raw_bass",
            "Description": items["ITEM-0050"].get("Description")
            or "A raw bass ready for the kitchen.",
        }
    )
    items["ITEM-0062"].update(
        {
            "Internal Key": "cooked_bass",
            "Display Name": "Cooked Bass",
            "Icon Asset Key": "cooked_bass",
            "Description": items["ITEM-0062"].get("Description")
            or "A cooked bass that restores health.",
        }
    )
    rename_asset("icons/items/item_raw_tuna.webp", "icons/items/item_raw_bass.webp")
    rename_asset("icons/items/item_cooked_tuna.webp", "icons/items/item_cooked_bass.webp")
    rename_asset("actions/acn_catch_tuna.webp", "actions/acn_catch_bass.webp")

    for a in db["Actions"]:
        if a.get("Action ID") == "ACN-0102":
            a.update(
                {
                    "Internal Key": "catch_bass",
                    "Display Name": "Catch bass",
                    "Sprite Asset Key": "actions/acn_catch_bass.webp",
                }
            )
        if a.get("Action ID") == "ACN-0123":
            a.update(
                {
                    "Internal Key": "cook_cooked_bass",
                    "Display Name": "Cooked bass",
                }
            )
        if a.get("Sprite Asset Key") == "actions/acn_catch_tuna.webp":
            a["Sprite Asset Key"] = "actions/acn_catch_bass.webp"

    for r in db["Recipes"]:
        if r.get("Recipe ID") == "RCP-0005":
            r.update(
                {
                    "Internal Key": "cook_cooked_bass",
                    "Display Name": "Cooked Bass",
                }
            )

    for e in rewards:
        name = e.get("Reward Table Name") or ""
        if "Raw Tuna" in name:
            e["Reward Table Name"] = name.replace("Raw Tuna", "Raw Bass")
        if "Cooked Tuna" in name:
            e["Reward Table Name"] = name.replace("Cooked Tuna", "Cooked Bass")

    # Activity / pool copy: tuna → bass
    for sheet in ("Activities", "PoolEntries", "Locations", "Config", "Projects", "NPCs", "Quests"):
        for row in db.get(sheet, []):
            for key, value in list(row.items()):
                if isinstance(value, str) and "tuna" in value.lower():
                    row[key] = (
                        value.replace("tuna", "bass")
                        .replace("Tuna", "Bass")
                        .replace("TUNA", "BASS")
                    )

    # Equipment notes on quiver: bow-gated (code enforces).
    for e in db["Equipment"]:
        if e.get("Item ID") == "ITEM-0303":
            e["Notes"] = (
                "Improves hunting experience by 5% while equipped with a bow "
                "(weapon has bow_combat_xp)."
            )
            e["Capabilities / Effects"] = "hunting_xp_bonus_percent:5; requires_bow"

    for c in db["Config"]:
        if c.get("Key") == "specialist.quiver_hunting_xp_factor":
            c["Notes"] = (
                "Hunting XP multiplier with a quiver equipped while a bow "
                "(bow_combat_xp) is in Weapon/Tool."
            )

    # Stale bar notes if still inverted
    if "ITEM-0080" in items:
        items["ITEM-0080"]["Notes"] = "Metallurgy 60. Tungsten combat gear requires Might/Vitality 60."
    if "ITEM-0079" in items:
        items["ITEM-0079"]["Notes"] = "Metallurgy 70. Titanium combat gear requires Might/Vitality 70."

    DB_PATH.write_text(json.dumps(db, indent=2, ensure_ascii=False) + "\n")
    flutter_db = ROOT / "app_flutter/content/data/game-database.json"
    if flutter_db.exists() and flutter_db.resolve() != DB_PATH.resolve():
        flutter_db.write_text(DB_PATH.read_text())
    print("patched drops / bass / quiver notes")


if __name__ == "__main__":
    main()
