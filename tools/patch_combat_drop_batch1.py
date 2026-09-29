#!/usr/bin/env python3
"""Combat drop tables batch 1: flatten qty variants, sync chances, new roost drops."""
from __future__ import annotations

import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "content/data/game-database.json"
ASSETS = ROOT / "content/assets/icons/items"

VERSION = "2026-09-29-combat-drops-batch1"

HARPY_FEATHERS = "ITEM-0419"
WYVERN_WING = "ITEM-0420"
GIANTS_TOE = "ITEM-0421"

RWT_HARPY = "RWT-0188"
RWT_WYVERN = "RWT-0189"
RWT_GIANT = "RWT-0190"


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
) -> None:
    """Replace all rows for table_id. entries: (entry_id, item_id, weight, qty)."""
    rewards[:] = [e for e in rewards if e.get("Reward Table ID") != table_id]
    for entry_id, item_id, weight, qty in entries:
        rewards.append(
            {
                "Reward Entry ID": entry_id,
                "Reward Table ID": table_id,
                "Reward Table Name": table_name,
                "Purpose": "Enemy item drops",
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


def sync_action_enemy(
    actions: dict[str, dict],
    enemies: dict[str, dict],
    action_id: str,
    *,
    drop_chance: float | int,
    reward_table: str | None,
    secondary_chance: float | int | None = None,
    secondary_table: str | None = None,
    notes: str | None = None,
) -> None:
    action = actions[action_id]
    enemy_id = action.get("Target ID")
    action["Drop Chance"] = drop_chance
    action["Reward Table ID"] = reward_table
    if secondary_chance is not None or secondary_table is not None:
        action["Secondary Drop Chance"] = secondary_chance
        action["Secondary Reward Table ID"] = secondary_table
    if notes is not None:
        action["Notes"] = notes
    if enemy_id and enemy_id in enemies:
        enemies[enemy_id]["Drop Chance"] = drop_chance
        enemies[enemy_id]["Reward Table ID"] = reward_table


def main() -> None:
    db = json.loads(DB_PATH.read_text())
    items = db["Items"]
    actions = {a["Action ID"]: a for a in db["Actions"]}
    enemies = {e["Enemy ID"]: e for e in db["Enemies"]}
    rewards = db["RewardEntries"]

    # --- New items + placeholder icons ---
    copy_icon("pheasant_feathers", "harpy_feathers")
    copy_icon("butterfly_wing", "wyvern_wing")
    copy_icon("boar_tusk", "giants_toe")

    upsert_item(
        items,
        HARPY_FEATHERS,
        {
            "Internal Key": "harpy_feathers",
            "Display Name": "Harpy Feathers",
            "Category": "Resource",
            "Subtype": "Creature material",
            "Associated Skill ID": "SKL-0001",
            "Equipment Slot ID": None,
            "Functional / Source Tags": "harpy_drop; special_material",
            "Status": "Planned",
            "Release Phase": "Launch",
            "Description": "Soft feathers shed by a mountain harpy.",
            "Icon Asset Key": "harpy_feathers",
            "Notes": "Placeholder art: pheasant feathers. Drop from Harpy.",
            "Base Sell Value": 180,
            "Stackable": None,
        },
    )
    upsert_item(
        items,
        WYVERN_WING,
        {
            "Internal Key": "wyvern_wing",
            "Display Name": "Wyvern Wing",
            "Category": "Resource",
            "Subtype": "Creature material",
            "Associated Skill ID": "SKL-0001",
            "Equipment Slot ID": None,
            "Functional / Source Tags": "wyvern_drop; special_material",
            "Status": "Planned",
            "Release Phase": "Launch",
            "Description": "A membrane wing torn from a wyvern.",
            "Icon Asset Key": "wyvern_wing",
            "Notes": "Placeholder art: butterfly wing. Drop from Wyvern.",
            "Base Sell Value": 420,
            "Stackable": None,
        },
    )
    upsert_item(
        items,
        GIANTS_TOE,
        {
            "Internal Key": "giants_toe",
            "Display Name": "Giant's Toe",
            "Category": "Resource",
            "Subtype": "Creature material",
            "Associated Skill ID": "SKL-0001",
            "Equipment Slot ID": None,
            "Functional / Source Tags": "giant_drop; special_material",
            "Status": "Planned",
            "Release Phase": "Launch",
            "Description": "A heavy toe cut from a mountain giant.",
            "Icon Asset Key": "giants_toe",
            "Notes": "Placeholder art: boar tusk. Drop from Giant.",
            "Base Sell Value": 350,
            "Stackable": None,
        },
    )

    # --- Main reward tables (no quantity variants; blank qty = 1) ---
    replace_table(
        rewards,
        "RWT-0001",
        "Cow Drops",
        [
            ("RWE-0001", "ITEM-0054", 40, 1),  # Beef
            ("RWE-0158", "ITEM-0378", 60, 1),  # Cowhide
        ],
    )
    replace_table(
        rewards,
        "RWT-0002",
        "Bull Drops",
        [
            ("RWE-0003", "ITEM-0054", 40, 2),  # 2 Beef
            ("RWE-0160", "ITEM-0378", 50, 2),  # 2 Cowhide
            ("RWE-0005", "ITEM-0040", 10, 1),  # Bull Horns
        ],
    )
    replace_table(
        rewards,
        "RWT-0003",
        "Goblin Scout Drops",
        [
            ("RWE-0008", "ITEM-0031", 40, 1),  # Fernleaf
            ("RWE-0007", "ITEM-0075", 35, 1),  # Bronze Bar
            ("RWE-0006", "ITEM-0225", 10, 1),  # Bronze Dagger
            ("RWE-9212", "ITEM-0060", 15, 1),  # Cooked Trout
        ],
    )
    replace_table(
        rewards,
        "RWT-0004",
        "Goblin Warrior Drops",
        [
            ("RWE-0010", "ITEM-0006", 40, 1),  # Coal
            ("RWE-0011", "ITEM-0005", 35, 1),  # Iron Ore
            ("RWE-0009", "ITEM-0225", 25, 1),  # Bronze Dagger
        ],
    )
    replace_table(
        rewards,
        "RWT-0005",
        "Goblin Chief Drops",
        [
            ("RWE-0013", "ITEM-0012", 40, 1),  # Sapphire
            ("RWE-0014", "ITEM-0013", 30, 1),  # Emerald
            ("RWE-0012", "ITEM-0129", 20, 1),  # Iron Dagger
            ("RWE-0015", "ITEM-0061", 10, 2),  # 2 Cooked Salmon
        ],
    )
    replace_table(
        rewards,
        "RWT-0007",
        "Wild Boar Drops",
        [
            ("RWE-0018", "ITEM-0194", 60, 1),  # Raw Boar Meat
            ("RWE-0019", "ITEM-0195", 30, 1),  # Boar Hide
            ("RWE-0020", "ITEM-0043", 10, 1),  # Boar Tusk
        ],
    )
    replace_table(
        rewards,
        "RWT-0008",
        "Skeleton Drops",
        [
            ("RWE-0022", "ITEM-0129", 80, 1),  # Iron Dagger
            ("RWE-0023", "ITEM-0012", 20, 1),  # Sapphire
        ],
    )
    replace_table(
        rewards,
        "RWT-0009",
        "Zombie Drops",
        [
            ("RWE-0024", "ITEM-0287", 88, 1),  # Grave Cloth
            ("RWE-0026", "ITEM-0013", 12, 1),  # Emerald
        ],
    )
    replace_table(
        rewards,
        "RWT-0010",
        "Guard Drops",
        [
            ("RWE-0027", "ITEM-0155", 40, 1),  # Iron Helmet
            ("RWE-0028", "ITEM-0147", 60, 1),  # Iron Shield
        ],
    )
    replace_table(
        rewards,
        "RWT-0011",
        "Pirate Drops",
        [
            ("RWE-0030", "ITEM-0131", 33, 1),  # Steel Dagger
            ("RWE-0031", "ITEM-0082", 60, 1),  # Gold Bar
            ("RWE-0033", "ITEM-0014", 5, 1),  # Ruby
            ("RWE-0179", "ITEM-0344", 2, 1),  # Pirate Hook
        ],
    )
    replace_table(
        rewards,
        "RWT-0012",
        "Rock Troll Drops",
        [
            ("RWE-0035", "ITEM-0006", 40, 1),  # Coal
            ("RWE-0034", "ITEM-0005", 35, 1),  # Iron Ore
            ("RWE-0036", "ITEM-0201", 23, 1),  # Troll Tooth
            ("RWE-0037", "ITEM-0014", 2, 1),  # Ruby
        ],
    )
    replace_table(
        rewards,
        "RWT-0013",
        "Ent Drops",
        [
            ("RWE-0038", "ITEM-0018", 55, 1),  # Maple Log
            ("RWE-0039", "ITEM-0202", 30, 1),  # Ancient Sap
            ("RWE-0040", "ITEM-0203", 15, 1),  # Ent Bark
        ],
    )
    replace_table(
        rewards,
        "RWT-0014",
        "Ancient Ent Drops",
        [
            ("RWE-0041", "ITEM-0330", 45, 1),  # Mahogany Sapling
            ("RWE-0043", "ITEM-0202", 20, 1),  # Ancient Sap
            ("RWE-0044", "ITEM-0204", 35, 1),  # Ancient Heartwood
        ],
    )
    replace_table(
        rewards,
        "RWT-0015",
        "Corrupted Ent Drops",
        [
            ("RWE-0046", "ITEM-0205", 40, 1),  # Corrupted Sap
            ("RWE-0047", "ITEM-0206", 45, 1),  # Heartwood
            ("RWE-0048", "ITEM-0011", 15, 1),  # Essence
        ],
    )
    replace_table(
        rewards,
        "RWT-0018",
        "Dragon Drops",
        [
            ("RWE-0057", "ITEM-0046", 50, 1),  # Dragon Scale
            ("RWE-0058", "ITEM-0014", 20, 1),  # Ruby
            ("RWE-0059", "ITEM-0079", 30, 1),  # Titanium Bar
        ],
    )
    # Cave bat / cyclops / pressure guards / secondary tables already correct shape;
    # only bat chance changes below.
    replace_table(
        rewards,
        "RWT-0186",
        "Cave Bat Drops",
        [("RWE-9210", "ITEM-0416", 100, 1)],
    )
    replace_table(
        rewards,
        "RWT-0187",
        "Cyclops Drops",
        [("RWE-9211", "ITEM-0418", 100, 1)],
    )
    replace_table(
        rewards,
        RWT_HARPY,
        "Harpy Drops",
        [("RWE-9213", HARPY_FEATHERS, 100, 1)],
    )
    replace_table(
        rewards,
        RWT_WYVERN,
        "Wyvern Drops",
        [("RWE-9214", WYVERN_WING, 100, 1)],
    )
    replace_table(
        rewards,
        RWT_GIANT,
        "Giant Drops",
        [
            ("RWE-9215", GIANTS_TOE, 50, 1),
            ("RWE-9216", "ITEM-0196", 25, 1),  # Goat Hide
            ("RWE-9217", "ITEM-0006", 25, 1),  # Coal
        ],
    )

    # Keep secondary singleton tables (weights already 100).
    for e in rewards:
        if e["Reward Table ID"] == "RWT-0115":
            e["Reward Table Name"] = "Goblin Staff Secondary"
            e["Purpose"] = "Independent Combat drop"
            e["Weight"] = 100
            e["Minimum Quantity"] = 1
            e["Maximum Quantity"] = 1
        if e["Reward Table ID"] == "RWT-0116":
            e["Reward Table Name"] = "Pirate Insignia Secondary"
            e["Purpose"] = "Independent Combat drop"
            e["Weight"] = 100
            e["Minimum Quantity"] = 1
            e["Maximum Quantity"] = 1
        if e["Reward Table ID"] == "RWT-0180":
            e["Notes"] = "One-time unlock of the Baby Dragon pet cosmetic."

    # --- Action + enemy drop chances / tables ---
    sync_action_enemy(actions, enemies, "ACN-0001", drop_chance=40, reward_table="RWT-0001")
    sync_action_enemy(actions, enemies, "ACN-0002", drop_chance=40, reward_table="RWT-0002")
    sync_action_enemy(actions, enemies, "ACN-0003", drop_chance=25, reward_table="RWT-0003")
    sync_action_enemy(actions, enemies, "ACN-0094", drop_chance=20, reward_table="RWT-0004")
    sync_action_enemy(
        actions,
        enemies,
        "ACN-0004",
        drop_chance=30,
        reward_table="RWT-0005",
        secondary_chance=50,
        secondary_table="RWT-0115",
        notes="Main gems/dagger/salmon. Goblin Staff secondary 50%.",
    )
    sync_action_enemy(actions, enemies, "ACN-0008", drop_chance=36, reward_table="RWT-0007")
    sync_action_enemy(actions, enemies, "ACN-0006", drop_chance=10, reward_table="RWT-0008")
    sync_action_enemy(actions, enemies, "ACN-0007", drop_chance=15, reward_table="RWT-0009")
    sync_action_enemy(
        actions,
        enemies,
        "ACN-0091",
        drop_chance=36,
        reward_table="RWT-0011",
        secondary_chance=10,
        secondary_table="RWT-0116",
        notes="Main dagger/bar/ruby/hook. Pirate Insignia secondary 10%.",
    )
    sync_action_enemy(actions, enemies, "ACN-0005", drop_chance=32, reward_table="RWT-0012")
    sync_action_enemy(actions, enemies, "ACN-0009", drop_chance=24, reward_table="RWT-0010")
    sync_action_enemy(actions, enemies, "ACN-0010", drop_chance=36, reward_table="RWT-0013")
    sync_action_enemy(actions, enemies, "ACN-0011", drop_chance=30, reward_table="RWT-0014")
    sync_action_enemy(actions, enemies, "ACN-0012", drop_chance=40, reward_table="RWT-0015")
    sync_action_enemy(
        actions,
        enemies,
        "ACN-0092",
        drop_chance=40,
        reward_table="RWT-0018",
        secondary_chance=1,
        secondary_table="RWT-0180",
        notes="Main scale/ruby/titanium. Baby Dragon pet secondary 1%.",
    )
    # Mother Squid shares rock troll main table.
    sync_action_enemy(actions, enemies, "ACN-0178", drop_chance=36, reward_table="RWT-0012")
    sync_action_enemy(
        actions,
        enemies,
        "ACN-0238",
        drop_chance=25,
        reward_table="RWT-0186",
        notes="Bat Wings 100% when the drop rolls (25% base).",
    )
    sync_action_enemy(actions, enemies, "ACN-0222", drop_chance=10, reward_table="RWT-0187")
    sync_action_enemy(actions, enemies, "ACN-0171", drop_chance=80, reward_table="RWT-0117")
    sync_action_enemy(
        actions,
        enemies,
        "ACN-0219",
        drop_chance=25,
        reward_table=RWT_HARPY,
        notes="Harpy Feathers 100% when the drop rolls (25% base).",
    )
    sync_action_enemy(
        actions,
        enemies,
        "ACN-0220",
        drop_chance=25,
        reward_table=RWT_WYVERN,
        notes="Wyvern Wing 100% when the drop rolls (25% base).",
    )
    sync_action_enemy(
        actions,
        enemies,
        "ACN-0221",
        drop_chance=20,
        reward_table=RWT_GIANT,
        notes="Giant's Toe / Goat Hide / Coal main table (20% base).",
    )

    # Hunt wild boar shares the same main table; leave its chance alone if already 36.
    if actions.get("ACN-0204"):
        actions["ACN-0204"]["Reward Table ID"] = "RWT-0007"

    # Bandits: gold only, base drop 0%.
    for aid, emin, emax, notes in (
        ("ACN-0235", 1, 2, "No item drops. Enemy gold 1–2."),
        ("ACN-0236", 5, 6, "No item drops. Enemy gold 5–6."),
    ):
        a = actions[aid]
        a["Drop Chance"] = 0
        a["Reward Table ID"] = None
        a["Notes"] = notes
        eid = a["Target ID"]
        enemies[eid]["Drop Chance"] = 0
        enemies[eid]["Reward Table ID"] = None
        enemies[eid]["Minimum Gold"] = emin
        enemies[eid]["Maximum Gold"] = emax
        enemies[eid]["Notes"] = notes

    enemies["ENM-0027"]["Notes"] = "Cave Bat. Bat Wings at 25% base drop chance."
    enemies["ENM-0030"]["Notes"] = "Mountain roost. Harpy Feathers at 25% base."
    enemies["ENM-0033"]["Notes"] = "Mountain roost. Wyvern Wing at 25% base."
    enemies["ENM-0031"]["Notes"] = "Giant camp. Giant's Toe / Goat Hide / Coal at 20% base."
    mother_notes = enemies["ENM-0023"].get("Notes") or ""
    if "shares_rock_troll_drops" not in mother_notes:
        enemies["ENM-0023"]["Notes"] = (
            f"{mother_notes}; shares_rock_troll_drops:RWT-0012"
            if mother_notes
            else "shares_rock_troll_drops:RWT-0012"
        )

    db["RewardEntries"] = rewards
    DB_PATH.write_text(json.dumps(db, indent=2) + "\n")
    print(f"Wrote {DB_PATH}")

    # Bump cache-bust versions
    ts = ROOT / "src/game/data/loadDatabase.ts"
    dart = ROOT / "packages/ik_content/lib/src/load_database.dart"
    ts.write_text(
        ts.read_text().replace(
            "2026-09-29-equipment-merge-enemy-mv",
            VERSION,
        )
    )
    dart.write_text(
        dart.read_text().replace(
            "2026-09-29-equipment-merge-enemy-mv",
            VERSION,
        )
    )
    print(f"Bumped content version to {VERSION}")


if __name__ == "__main__":
    main()
