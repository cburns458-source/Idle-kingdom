#!/usr/bin/env python3
"""Content patch: copper pool, rabbit hide, luck scopes, combat XP = floor(hp/2)."""

from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB_PATHS = [
    ROOT / "content" / "data" / "game-database.json",
    ROOT / "app_flutter" / "content" / "data" / "game-database.json",
]


def vitality_level(enemy: dict) -> int:
    vit = enemy.get("Vitality Level")
    if isinstance(vit, (int, float)):
        return int(vit)
    combat = enemy.get("Combat Level")
    if isinstance(combat, (int, float)):
        return int(combat)
    return 1


def scaled_max_hp(enemy: dict) -> int:
    hp = enemy.get("Maximum HP") or 0
    try:
        hp = float(hp)
    except (TypeError, ValueError):
        hp = 0
    level = vitality_level(enemy)
    bonus = 1.0 if level < 10 else 1.0 + level * 0.01
    return max(1, int(math.floor(hp * bonus)))


def patch_db(db: dict) -> dict:
    # Copper mine pool: 60 / 20 / 20
    for pen_id, weight, note in (
        ("PEN-0141", 60, "Copper 60%."),
        ("PEN-0142", 20, "Tin 20%."),
        ("PEN-0143", 20, "Clay 20%."),
    ):
        for row in db["PoolEntries"]:
            if row.get("Pool Entry ID") == pen_id:
                row["Weight"] = weight
                row["Notes"] = note

    # Luck potions: usable for gathering one_action and combat one_combat_encounter
    for eqp_id, bonus in (("EQP-0014", 25), ("EQP-0106", 10)):
        for row in db["Equipment"]:
            if row.get("Equipment ID") == eqp_id:
                row["Capabilities / Effects"] = (
                    f"potion_slot; one_action; one_combat_encounter; "
                    f"+{bonus}% relative Drop Chance"
                )
                notes = row.get("Notes") or ""
                if "Action or Combat" not in notes:
                    row["Notes"] = (
                        (notes + " " if notes else "")
                        + "Applies to main Drop Chance for gathering/thievery (per action) "
                        "and combat (per encounter)."
                    ).strip()

    # Rabbit hide item
    if not any(row.get("Item ID") == "ITEM-0424" for row in db["Items"]):
        goat = next(row for row in db["Items"] if row.get("Item ID") == "ITEM-0196")
        rabbit_hide = dict(goat)
        rabbit_hide.update(
            {
                "Item ID": "ITEM-0424",
                "Internal Key": "rabbit_hide",
                "Display Name": "Rabbit Hide",
                "Subtype": "Creature material",
                "Associated Skill ID": "SKL-0005",
                "Functional / Source Tags": "hunting_output; crafting_input",
                "Icon Asset Key": "goat_hide",
                "Base Sell Value": 40,
                "Notes": "Tanner turns into 1 leather.",
                "Status": "Planned",
                "Release Phase": "Launch",
            }
        )
        db["Items"].append(rabbit_hide)

    # Rabbit drop weights: meat 60 / hide 30 / foot 10
    for row in db["RewardEntries"]:
        if row.get("Reward Entry ID") == "RWE-0092":
            row["Weight"] = 60
            row["Notes"] = "Raw Rabbit 60%."
        elif row.get("Reward Entry ID") == "RWE-0107":
            row["Weight"] = 10
            row["Notes"] = "Rabbit's Foot 10%."
    if not any(
        row.get("Reward Entry ID") == "RWE-9226" for row in db["RewardEntries"]
    ):
        template = next(
            row for row in db["RewardEntries"] if row.get("Reward Entry ID") == "RWE-0092"
        )
        hide_entry = dict(template)
        hide_entry.update(
            {
                "Reward Entry ID": "RWE-9226",
                "Reward Table ID": "RWT-0050",
                "Reward Table Name": "Rabbit Drops",
                "Reward ID / Value": "ITEM-0424",
                "Weight": 30,
                "Notes": "Rabbit Hide 30%.",
            }
        )
        db["RewardEntries"].append(hide_entry)

    for row in db["Actions"]:
        if row.get("Action ID") == "ACN-0016":
            row["Notes"] = (
                "Raw Rabbit 60% / Rabbit Hide 30% / Rabbit's Foot 10% main. "
                "Animal Tendons secondary 5%."
            )

    # Combat XP = floor(scaledMaxHp / 2)
    for enemy in db["Enemies"]:
        if not isinstance(enemy.get("Maximum HP"), (int, float)):
            continue
        enemy["Combat XP"] = scaled_max_hp(enemy) // 2

    return db


def main() -> None:
    for path in DB_PATHS:
        db = json.loads(path.read_text())
        patch_db(db)
        path.write_text(json.dumps(db, indent=2, ensure_ascii=False) + "\n")
        print(f"patched {path}")


if __name__ == "__main__":
    main()
