#!/usr/bin/env python3
"""Port stranded balance content onto test-launch without clobbering trunk-only rows.

- Copper mine pool 60/20/20
- Rabbit Hide as ITEM-0426 (ITEM-0424 is Cooked Duck on trunk)
- Luck potion dual scopes
- Willow/yew/weasel primary nerfs + sapling secondaries + boots off rods
- Combat timing #286 (both @6, eat_at 1)
- Race-change costs as Config rows (current trunk values)
- Strip thievery FailChance notes (keep FailDamagePercent)
"""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB_PATHS = [
    ROOT / "content" / "data" / "game-database.json",
    ROOT / "app_flutter" / "content" / "data" / "game-database.json",
]

RABBIT_HIDE_ID = "ITEM-0426"
RABBIT_HIDE_REWARD_ID = "RWE-9227"

PRIMARY_DROPS = {
    "ACN-0200": (30, "Willow 30% primary."),
    "ACN-0051": (25, "Elder yew 25% primary."),
    "ACN-0015": (30, None),
}

SAPLING_ACTIONS = (
    "ACN-0046",
    "ACN-0047",
    "ACN-0048",
    "ACN-0049",
    "ACN-0050",
    "ACN-0051",
    "ACN-0200",
    "ACN-0202",
)

ROD_BOOT_ACTIONS = (
    "ACN-0099",
    "ACN-0100",
    "ACN-0101",
    "ACN-0102",
    "ACN-0103",
    "ACN-0104",
)

RACE_COSTS = {
    "RACE-0001": {"gold": 0, "items": "ITEM-0018:40"},
    "RACE-0002": {"gold": 0, "items": "ITEM-0041:20,ITEM-0196:20"},
    "RACE-0003": {"gold": 0, "items": "ITEM-0050:40"},
    "RACE-0004": {"gold": 0, "items": "ITEM-0045:20,ITEM-0041:15"},
    "RACE-0005": {"gold": 5000, "items": "ITEM-0077:20"},
    "RACE-0006": {"gold": 0, "items": "ITEM-0005:60,ITEM-0006:20,ITEM-0007:20"},
    "RACE-0007": {"gold": 0, "items": "ITEM-0028:40,ITEM-0033:20"},
}


def upsert_config(db: dict, key: str, value, unit: str | None, notes: str) -> None:
    for row in db["Config"]:
        if row.get("Key") == key:
            row["Value"] = value
            if unit is not None:
                row["Unit"] = unit
            row["Notes"] = notes
            return
    db["Config"].append(
        {"Key": key, "Value": value, "Unit": unit, "Notes": notes},
    )


def patch_db(db: dict) -> None:
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

    # Luck potions: gathering one_action + combat one_combat_encounter
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

    # Rabbit hide (new ID — ITEM-0424 is Cooked Duck on trunk)
    if not any(row.get("Item ID") == RABBIT_HIDE_ID for row in db["Items"]):
        goat = next(row for row in db["Items"] if row.get("Item ID") == "ITEM-0196")
        rabbit_hide = dict(goat)
        rabbit_hide.update(
            {
                "Item ID": RABBIT_HIDE_ID,
                "Internal Key": "rabbit_hide",
                "Display Name": "Rabbit Hide",
                "Category": "Resource",
                "Subtype": "Creature material",
                "Associated Skill ID": "SKL-0005",
                "Equipment Slot ID": None,
                "Functional / Source Tags": "hunting_output; crafting_input",
                "Icon Asset Key": "rabbit_hide",
                "Base Sell Value": 40,
                "Notes": "Tanner turns into 1 leather.",
                "Status": "Planned",
                "Release Phase": "Launch",
                "Description": goat.get("Description"),
            }
        )
        db["Items"].append(rabbit_hide)

    for row in db["RewardEntries"]:
        if row.get("Reward Entry ID") == "RWE-0092":
            row["Weight"] = 60
            row["Notes"] = "Raw Rabbit 60%."
        elif row.get("Reward Entry ID") == "RWE-0107":
            row["Weight"] = 10
            row["Notes"] = "Rabbit's Foot 10%."
        elif row.get("Reward Entry ID") == RABBIT_HIDE_REWARD_ID:
            row["Reward ID / Value"] = RABBIT_HIDE_ID
            row["Weight"] = 30
            row["Notes"] = "Rabbit Hide 30%."
    if not any(row.get("Reward Entry ID") == RABBIT_HIDE_REWARD_ID for row in db["RewardEntries"]):
        template = next(
            row for row in db["RewardEntries"] if row.get("Reward Entry ID") == "RWE-0092"
        )
        hide_entry = dict(template)
        hide_entry.update(
            {
                "Reward Entry ID": RABBIT_HIDE_REWARD_ID,
                "Reward Table ID": "RWT-0050",
                "Reward Table Name": "Rabbit Drops",
                "Reward ID / Value": RABBIT_HIDE_ID,
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

    # Drop nerfs + saplings + boots off rods
    for action in db["Actions"]:
        action_id = action.get("Action ID")
        if action_id in PRIMARY_DROPS:
            chance, note = PRIMARY_DROPS[action_id]
            action["Drop Chance"] = chance
            if action_id == "ACN-0015":
                action["Notes"] = (
                    "Weasel Tail 100% when the drop rolls (30% drop chance). No tendons."
                )
            elif note:
                notes = action.get("Notes") or ""
                if note not in notes:
                    action["Notes"] = (notes + " " + note).strip()
        if action_id in SAPLING_ACTIONS and action.get("Secondary Reward Table ID"):
            action["Secondary Drop Chance"] = 0.1
            notes = action.get("Notes") or ""
            notes = notes.replace("Sapling secondary 0.5%.", "Sapling secondary 0.1%.")
            if "Sapling secondary 0.1%." not in notes:
                notes = (notes + " Sapling secondary 0.1%.").strip()
            action["Notes"] = notes
        if action_id in ROD_BOOT_ACTIONS:
            action["Secondary Reward Table ID"] = None
            action["Secondary Drop Chance"] = None
            notes = action.get("Notes") or ""
            notes = (
                notes.replace("Old Boots secondary 1%.", "")
                .replace("Old Boots secondary.", "")
                .strip()
            )
            while "Old Boots moved to pot fishing." in notes:
                notes = notes.replace("Old Boots moved to pot fishing.", "").strip()
            action["Notes"] = (notes + " Old Boots moved to pot fishing.").strip()

        # Thievery: remove FailChance; keep FailDamagePercent; kitchen loses NoConsequences
        notes = action.get("Notes") or ""
        if "Thievery" in notes or "FailChance:" in notes or "NoConsequences" in notes:
            cleaned = re.sub(r"\s*FailChance:\d+;?", "", notes)
            cleaned = re.sub(r"\s*NoConsequences;?", "", cleaned)
            cleaned = re.sub(r"\s{2,}", " ", cleaned).strip(" ;")
            if "ThieverySteal" in cleaned and "FailDamagePercent" not in cleaned:
                cleaned = (cleaned + "; FailDamagePercent:10").strip(" ;")
            if cleaned != notes:
                action["Notes"] = cleaned or None

    for item in db["Items"]:
        if item.get("Item ID") == "ITEM-0347":
            item["Notes"] = (
                "Place at Goblin Camp or the Docks. Up to three pots per site per UTC day, "
                "one at a time; 6 hour soak. Old Boots 1% secondary per collect."
            )

    # Combat timing #286
    upsert_config(
        db,
        "combat_round_duration",
        6,
        "seconds",
        "Combat round length. Hits and outcomes resolve together at "
        "combat_player_attack_at / combat_enemy_attack_at (round end). "
        "Mid-round auto-eat uses combat_eat_at. No extra eat delay.",
    )
    upsert_config(
        db,
        "combat_eat_between_seconds",
        0,
        "seconds",
        "Legacy inter-round eat pause. Unused; auto-eat is combat_eat_at inside the round.",
    )
    upsert_config(
        db,
        "combat_eat_at",
        1,
        "seconds",
        "Seconds into a combat round when auto-eat resolves. Instant; does not extend "
        "the round. Timed so previous-round hit numbers have finished fading.",
    )
    upsert_config(
        db,
        "combat_enemy_attack_at",
        6,
        "seconds",
        "Seconds into a combat round when the enemy attacks (same time as the player). "
        "Skipped on a killing blow. Same as combat_round_duration so the bar stays continuous.",
    )
    upsert_config(
        db,
        "combat_player_attack_at",
        6,
        "seconds",
        "Seconds into a combat round when the player attacks (same time as the enemy). "
        "Same as combat_round_duration so hits and the next round share one beat.",
    )

    # Race-change costs (current trunk values)
    for race_id, cost in RACE_COSTS.items():
        upsert_config(
            db,
            f"race_change_cost_{race_id}_items",
            cost["items"],
            None,
            f"Vesper race-change item costs for {race_id} (itemId:qty, comma-separated).",
        )
        if cost["gold"]:
            upsert_config(
                db,
                f"race_change_cost_{race_id}_gold",
                cost["gold"],
                "gold",
                f"Vesper race-change gold cost for {race_id}.",
            )


def main() -> None:
    for path in DB_PATHS:
        if not path.exists():
            continue
        db = json.loads(path.read_text())
        patch_db(db)
        path.write_text(json.dumps(db, indent=2, ensure_ascii=False) + "\n")
        print(f"patched {path}")


if __name__ == "__main__":
    main()
