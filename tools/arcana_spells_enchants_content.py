#!/usr/bin/env python3
"""Apply Arcana spell/enchant content ladder to game-database.json."""

from __future__ import annotations

import json
from copy import deepcopy
from pathlib import Path

DB_PATH = Path("content/data/game-database.json")

TABLET_E = "ITEM-0098"
TABLET_S = "ITEM-0099"
ESSENCE = "ITEM-0011"
FAC = "FAC-0008"
ARC = "SKL-0013"


def upsert(rows: list, key: str, row: dict) -> None:
    for i, existing in enumerate(rows):
        if existing.get(key) == row[key]:
            rows[i] = row
            return
    rows.append(row)


def project(
    pid: str,
    key: str,
    name: str,
    output: str,
    level: int,
    xp: int,
    inputs: list[tuple[str, int]],
    notes: str | None = None,
    status: str = "Planned",
    phase: str = "Launch",
) -> dict:
    row = {
        "Project ID": pid,
        "Internal Key": key,
        "Display Name": name,
        "Skill ID": ARC,
        "Output Item / Target ID": output,
        "Output Quantity": 1,
        "Facility ID": FAC,
        "Recipe ID": None,
        "XP Reward": xp,
        "Gold Cost": 0,
        "Instant": "Yes",
        "Status": status,
        "Release Phase": phase,
        "Notes": notes,
        "Input 1 Item ID": None,
        "Input 1 Quantity": None,
        "Input 2 Item ID": None,
        "Input 2 Quantity": None,
        "Input 3 Item ID": None,
        "Input 3 Quantity": None,
        "Input 4 Item ID": None,
        "Input 4 Quantity": None,
        "Required Skill 1 ID": ARC,
        "Required Skill 1 Level": level,
        "Required Skill 2 ID": None,
        "Required Skill 2 Level": None,
        "Required Skill 3 ID": None,
        "Required Skill 3 Level": None,
    }
    for i, (item_id, qty) in enumerate(inputs, start=1):
        row[f"Input {i} Item ID"] = item_id
        row[f"Input {i} Quantity"] = qty
    return row


def ench(
    eid: str,
    key: str,
    name: str,
    target: str,
    effect: str,
    mats: str,
    notes: str | None = None,
    status: str = "Planned",
    phase: str = "Launch",
) -> dict:
    return {
        "Enchantment ID": eid,
        "Internal Key": key,
        "Display Name": name,
        "Valid Target": target,
        "Effect": effect,
        "Required Materials": mats,
        "Status": status,
        "Release Phase": phase,
        "Notes": notes,
    }


def spell_item(
    iid: str,
    key: str,
    name: str,
    subtype: str,
    ench_id: str,
    description: str,
    sell: int,
    icon: str,
) -> dict:
    return {
        "Item ID": iid,
        "Internal Key": key,
        "Display Name": name,
        "Category": "Spell",
        "Subtype": subtype,
        "Associated Skill ID": ARC,
        "Equipment Slot ID": "SLOT-0013",
        "Functional / Source Tags": f"spell; spell_effect:{ench_id}; arcana_output; spell_stacks",
        "Status": "Planned",
        "Release Phase": "Launch",
        "Description": description,
        "Icon Asset Key": icon,
        "Notes": "Crafted at the Arcana Facility. May fill any spell slot; duplicates allowed.",
        "Base Sell Value": sell,
        "Stackable": None,
    }


def spell_eq(eid: str, iid: str, caps: str) -> dict:
    return {
        "Equipment ID": eid,
        "Item ID": iid,
        "Slot ID": "SLOT-0013",
        "Required Skill ID": ARC,
        "Required Level": 1,
        "Secondary Required Skill ID": None,
        "Secondary Required Level": None,
        "Min Damage": None,
        "Max Damage": None,
        "HP Bonus": None,
        "Damage Reduction": None,
        "Healing Amount": None,
        "Action Time Reduction %": None,
        "Capabilities / Effects": caps,
        "Status": "Confirmed",
        "Notes": "May be equipped to any Spell slot (SLOT-0013–SLOT-0016).",
    }


def main() -> None:
    db = json.loads(DB_PATH.read_text())

    # --- Enchantments: rework / retire / add ---
    by_ench = {e["Enchantment ID"]: e for e in db["Enchantments"]}

    # Compat: keep ENCH-0002 readable for old saves; mark notes.
    by_ench["ENCH-0002"] = ench(
        "ENCH-0002",
        "minor_gathering_enchantment",
        "Minor Gathering Enchantment",
        "Eligible gathering equipment",
        "-2% eligible Gathering Action duration",
        "Enchanting Tablet; Essence; Fernleaf",
        notes="Legacy. Superseded by skill-specific Minor Mining/Fishing/Woodcutting. Still applies if already enchanted.",
        status="Planned",
    )

    by_ench["ENCH-0003"] = ench(
        "ENCH-0003",
        "minor_strength_enchantment",
        "Minor Strength Enchantment",
        "Eligible weapon",
        "+5% damage range while enchanted",
        "Enchanting Tablet; Essence; Bull Horns",
        notes="Reworked from Minor Combat (+20 flat damage).",
    )

    by_ench["ENCH-0004"] = ench(
        "ENCH-0004",
        "ancient_weapon_enchantment",
        "Ancient Weapon Enchantment",
        "Eligible weapon",
        "+10% weapon Damage Range before final rounding",
        "Enchanting Tablets; Essence; Ancient Heartwood",
        notes="Retired from the Arcana ladder.",
        status="Retired",
        phase="Expansion",
    )

    new_ench = [
        ench(
            "ENCH-0010",
            "minor_mining_enchantment",
            "Minor Mining Enchantment",
            "Eligible mining tool",
            "-2% Mining Action duration",
            "Enchanting Tablet; Essence; Coal",
        ),
        ench(
            "ENCH-0011",
            "minor_fishing_enchantment",
            "Minor Fishing Enchantment",
            "Eligible fishing tool",
            "-2% Fishing Action duration",
            "Enchanting Tablet; Essence; Kelp",
        ),
        ench(
            "ENCH-0012",
            "minor_woodcutting_enchantment",
            "Minor Woodcutting Enchantment",
            "Eligible woodcutting tool",
            "-2% Woodcutting Action duration",
            "Enchanting Tablet; Essence; Cedar Log",
        ),
        ench(
            "ENCH-0013",
            "vital_plating_enchantment",
            "Vital Plating",
            "Eligible armor",
            "+5% maximum HP",
            "Enchanting Tablet; Essence; Leather",
        ),
        ench(
            "ENCH-0014",
            "combat_enchantment",
            "Combat Enchantment",
            "Eligible weapon",
            "+10% damage range while enchanted",
            "Enchanting Tablet; Essence; Boar Tusk",
        ),
        ench(
            "ENCH-0015",
            "mining_enchantment",
            "Mining Enchantment",
            "Eligible mining tool",
            "+5% Mining action time reduction",
            "Enchanting Tablet; Essence; Iron Ore",
        ),
        ench(
            "ENCH-0016",
            "fishing_enchantment",
            "Fishing Enchantment",
            "Eligible fishing tool",
            "+5% Fishing action time reduction",
            "Enchanting Tablet; Essence; Raw Eel",
        ),
        ench(
            "ENCH-0017",
            "woodcutting_enchantment",
            "Woodcutting Enchantment",
            "Eligible woodcutting tool",
            "+5% Woodcutting action time reduction",
            "Enchanting Tablet; Essence; Oak Log",
        ),
        ench(
            "ENCH-0018",
            "double_shot_enchantment",
            "Double Shot",
            "Eligible bow",
            "50% chance to attack twice each combat round",
            "Enchanting Tablet; Essence; Pheasant Feathers",
        ),
        ench(
            "ENCH-0019",
            "major_combat_enchantment",
            "Major Combat Enchantment",
            "Eligible weapon",
            "+15% damage range while enchanted",
            "Enchanting Tablet; Essence; Moonhorn Antler",
        ),
        ench(
            "ENCH-0020",
            "major_mining_enchantment",
            "Major Mining Enchantment",
            "Eligible mining tool",
            "+10% Mining action time reduction",
            "Enchanting Tablet; Essence; Troll Tooth",
        ),
        ench(
            "ENCH-0021",
            "major_fishing_enchantment",
            "Major Fishing Enchantment",
            "Eligible fishing tool",
            "+10% Fishing action time reduction",
            "Enchanting Tablet; Essence; Algae",
        ),
        ench(
            "ENCH-0022",
            "major_woodcutting_enchantment",
            "Major Woodcutting Enchantment",
            "Eligible woodcutting tool",
            "+10% Woodcutting action time reduction",
            "Enchanting Tablet; Essence; Ancient Sap",
        ),
        # Spell effect records
        ench(
            "ENCH-0023",
            "hoard_spell",
            "Hoard",
            "Spell slot / player",
            "+10% chance to double gold gained on combat victory",
            "Spell Tablet; Gold Ring; Essence",
            status="Confirmed",
            notes="Player spell. Stacks additively.",
        ),
        ench(
            "ENCH-0024",
            "iron_ward_spell",
            "Iron Ward",
            "Spell slot / player",
            "+5% damage reduction while equipped",
            "Spell Tablet; Iron Bar; Essence",
            status="Confirmed",
            notes="Player spell. Stacks additively per equipped copy.",
        ),
        ench(
            "ENCH-0025",
            "lifesteal_spell",
            "Lifesteal",
            "Spell slot / player",
            "+5% damage range and heal 5% of damage dealt at the end of each combat round",
            "Spell Tablet; Bleeding Tooth; Essence",
            status="Confirmed",
            notes="Player spell. Stacks additively.",
        ),
        ench(
            "ENCH-0026",
            "warrior_might_spell",
            "Warrior Might",
            "Spell slot / player",
            "+15% damage range while equipped",
            "Spell Tablet; Bull Horns; Essence",
            status="Confirmed",
            notes="Player spell. Stacks additively.",
        ),
        ench(
            "ENCH-0027",
            "haste_spell",
            "Haste",
            "Spell slot / player",
            "-10% production craft duration while equipped",
            "Spell Tablet; Speed Potion; Essence",
            status="Confirmed",
            notes="Player spell. Stacks additively.",
        ),
        ench(
            "ENCH-0028",
            "pathfinder_spell",
            "Pathfinder",
            "Spell slot / player",
            "-10% gathering action duration while equipped",
            "Spell Tablet; Starroot; Essence",
            status="Confirmed",
            notes="Player spell. Stacks additively.",
        ),
    ]
    for row in new_ench:
        by_ench[row["Enchantment ID"]] = row
    db["Enchantments"] = sorted(by_ench.values(), key=lambda r: r["Enchantment ID"])

    # --- Spell items + equipment ---
    spells = [
        (
            "ITEM-0394",
            "EQP-0210",
            "hoard_spell",
            "Hoard Spell",
            "Wealth spell",
            "ENCH-0023",
            "gold_double_chance_percent:10",
            "A prepared Hoard spell. While equipped, gold from combat victories has a chance to double. Duplicates stack.",
            1600,
        ),
        (
            "ITEM-0395",
            "EQP-0211",
            "iron_ward_spell",
            "Iron Ward Spell",
            "Combat spell",
            "ENCH-0024",
            "damage_reduction_percent:5",
            "A prepared Iron Ward spell. While equipped, gain damage reduction. Duplicates stack.",
            1800,
        ),
        (
            "ITEM-0396",
            "EQP-0212",
            "lifesteal_spell",
            "Lifesteal Spell",
            "Combat spell",
            "ENCH-0025",
            "damage_range_bonus_percent:5; lifesteal_percent:5",
            "A prepared Lifesteal spell. While equipped, deal more damage and heal from damage dealt each round. Duplicates stack.",
            2200,
        ),
        (
            "ITEM-0397",
            "EQP-0213",
            "warrior_might_spell",
            "Warrior Might Spell",
            "Combat spell",
            "ENCH-0026",
            "damage_range_bonus_percent:15",
            "A prepared Warrior Might spell. While equipped, gain a large damage-range bonus. Duplicates stack.",
            2800,
        ),
        (
            "ITEM-0398",
            "EQP-0214",
            "haste_spell",
            "Haste Spell",
            "Production spell",
            "ENCH-0027",
            "production_duration_reduction_percent:10",
            "A prepared Haste spell. While equipped, production crafts complete faster. Duplicates stack.",
            3000,
        ),
        (
            "ITEM-0399",
            "EQP-0215",
            "pathfinder_spell",
            "Pathfinder Spell",
            "Gathering spell",
            "ENCH-0028",
            "gathering_duration_reduction_percent:10",
            "A prepared Pathfinder spell. While equipped, gathering actions complete faster. Duplicates stack.",
            3500,
        ),
    ]
    for iid, eqid, key, name, subtype, ench_id, tag, desc, sell in spells:
        upsert(
            db["Items"],
            "Item ID",
            spell_item(iid, key, name, subtype, ench_id, desc, sell, key),
        )
        caps = f"spell; spell_effect:{ench_id}; {tag}; spell_stacks"
        upsert(db["Equipment"], "Equipment ID", spell_eq(eqid, iid, caps))

    # --- Projects ---
    by_proj = {p["Project ID"]: p for p in db["Projects"]}

    # Rework / retire
    by_proj["PRJ-0135"] = project(
        "PRJ-0135",
        "arcana_minor_strength",
        "Minor Strength Enchantment",
        "ENCH-0003",
        10,
        25000,
        [(TABLET_E, 1), (ESSENCE, 30), ("ITEM-0040", 1)],
        notes="Arcana 10. Enchanting Tablet + Bull Horns. Weapons. +5% damage range.",
    )
    by_proj["PRJ-0134"] = project(
        "PRJ-0134",
        "arcana_minor_gathering",
        "Minor Gathering Enchantment",
        "ENCH-0002",
        20,
        60000,
        [(TABLET_E, 1), (ESSENCE, 20), ("ITEM-0031", 10)],
        notes="Retired from the ladder; superseded by Minor Mining/Fishing/Woodcutting.",
        status="Retired",
    )
    by_proj["PRJ-0138"] = project(
        "PRJ-0138",
        "arcana_ancient_weapon",
        "Ancient Weapon Enchantment",
        "ENCH-0004",
        80,
        4000000,
        [(TABLET_E, 5), (ESSENCE, 30), ("ITEM-0204", 1)],
        notes="Retired from the Arcana ladder.",
        status="Retired",
        phase="Expansion",
    )

    new_projects = [
        project(
            "PRJ-0159",
            "arcana_minor_mining",
            "Minor Mining Enchantment",
            "ENCH-0010",
            20,
            60000,
            [(TABLET_E, 1), (ESSENCE, 20), ("ITEM-0006", 10)],
            notes="Arcana 20. Pickaxes. -2% Mining action duration.",
        ),
        project(
            "PRJ-0160",
            "arcana_minor_fishing",
            "Minor Fishing Enchantment",
            "ENCH-0011",
            20,
            60000,
            [(TABLET_E, 1), (ESSENCE, 20), ("ITEM-0342", 10)],
            notes="Arcana 20. Fishing tools. -2% Fishing action duration.",
        ),
        project(
            "PRJ-0161",
            "arcana_minor_woodcutting",
            "Minor Woodcutting Enchantment",
            "ENCH-0012",
            20,
            60000,
            [(TABLET_E, 1), (ESSENCE, 20), ("ITEM-0015", 10)],
            notes="Arcana 20. Hatchets. -2% Woodcutting action duration.",
        ),
        project(
            "PRJ-0162",
            "arcana_vital_plating",
            "Vital Plating",
            "ENCH-0013",
            25,
            90000,
            [(TABLET_E, 1), (ESSENCE, 40), ("ITEM-0045", 5)],
            notes="Arcana 25. Armor only. +5% maximum HP.",
        ),
        project(
            "PRJ-0163",
            "arcana_combat_enchantment",
            "Combat Enchantment",
            "ENCH-0014",
            40,
            180000,
            [(TABLET_E, 1), (ESSENCE, 60), ("ITEM-0043", 2)],
            notes="Arcana 40. Weapons. +10% damage range.",
        ),
        project(
            "PRJ-0164",
            "arcana_mining_enchantment",
            "Mining Enchantment",
            "ENCH-0015",
            45,
            200000,
            [(TABLET_E, 1), (ESSENCE, 60), ("ITEM-0005", 15)],
            notes="Arcana 45. Pickaxes. +5% Mining ATR.",
        ),
        project(
            "PRJ-0165",
            "arcana_fishing_enchantment",
            "Fishing Enchantment",
            "ENCH-0016",
            45,
            200000,
            [(TABLET_E, 1), (ESSENCE, 60), ("ITEM-0356", 8)],
            notes="Arcana 45. Fishing tools. +5% Fishing ATR.",
        ),
        project(
            "PRJ-0166",
            "arcana_woodcutting_enchantment",
            "Woodcutting Enchantment",
            "ENCH-0017",
            45,
            200000,
            [(TABLET_E, 1), (ESSENCE, 60), ("ITEM-0016", 12)],
            notes="Arcana 45. Hatchets. +5% Woodcutting ATR.",
        ),
        project(
            "PRJ-0167",
            "arcana_hoard_spell",
            "Hoard Spell",
            "ITEM-0394",
            50,
            400000,
            [(TABLET_S, 1), ("ITEM-0173", 1), (ESSENCE, 100)],
            notes="Creates the Hoard Spell (+10% chance to double gold on victory).",
        ),
        project(
            "PRJ-0168",
            "arcana_double_shot",
            "Double Shot",
            "ENCH-0018",
            60,
            500000,
            [(TABLET_E, 2), (ESSENCE, 80), ("ITEM-0039", 20)],
            notes="Arcana 60. Bows only. 50% chance to attack twice.",
        ),
        project(
            "PRJ-0169",
            "arcana_iron_ward_spell",
            "Iron Ward Spell",
            "ITEM-0395",
            60,
            550000,
            [(TABLET_S, 1), ("ITEM-0076", 5), (ESSENCE, 120)],
            notes="Creates the Iron Ward Spell (+5% damage reduction per copy).",
        ),
        project(
            "PRJ-0170",
            "arcana_major_combat",
            "Major Combat Enchantment",
            "ENCH-0019",
            70,
            700000,
            [(TABLET_E, 2), (ESSENCE, 100), ("ITEM-0200", 1)],
            notes="Arcana 70. Weapons. +15% damage range.",
        ),
        project(
            "PRJ-0171",
            "arcana_lifesteal_spell",
            "Lifesteal Spell",
            "ITEM-0396",
            70,
            750000,
            [(TABLET_S, 1), ("ITEM-0388", 3), (ESSENCE, 140)],
            notes="Creates the Lifesteal Spell (+5% damage range and 5% heal from damage dealt).",
        ),
        project(
            "PRJ-0172",
            "arcana_major_mining",
            "Major Mining Enchantment",
            "ENCH-0020",
            75,
            850000,
            [(TABLET_E, 2), (ESSENCE, 110), ("ITEM-0201", 2)],
            notes="Arcana 75. Pickaxes. +10% Mining ATR.",
        ),
        project(
            "PRJ-0173",
            "arcana_major_fishing",
            "Major Fishing Enchantment",
            "ENCH-0021",
            75,
            850000,
            [(TABLET_E, 2), (ESSENCE, 110), ("ITEM-0319", 15)],
            notes="Arcana 75. Fishing tools. +10% Fishing ATR.",
        ),
        project(
            "PRJ-0174",
            "arcana_major_woodcutting",
            "Major Woodcutting Enchantment",
            "ENCH-0022",
            75,
            850000,
            [(TABLET_E, 2), (ESSENCE, 110), ("ITEM-0202", 3)],
            notes="Arcana 75. Hatchets. +10% Woodcutting ATR.",
        ),
        project(
            "PRJ-0175",
            "arcana_warrior_might_spell",
            "Warrior Might Spell",
            "ITEM-0397",
            80,
            1200000,
            [(TABLET_S, 2), ("ITEM-0040", 20), (ESSENCE, 200)],
            notes="Creates the Warrior Might Spell (+15% damage range).",
        ),
        project(
            "PRJ-0176",
            "arcana_haste_spell",
            "Haste Spell",
            "ITEM-0398",
            90,
            1800000,
            [(TABLET_S, 2), ("ITEM-0071", 5), (ESSENCE, 250)],
            notes="Creates the Haste Spell (-10% production craft duration).",
        ),
        project(
            "PRJ-0177",
            "arcana_pathfinder_spell",
            "Pathfinder Spell",
            "ITEM-0399",
            100,
            2500000,
            [(TABLET_S, 3), ("ITEM-0208", 5), (ESSENCE, 300)],
            notes="Creates the Pathfinder Spell (-10% gathering action duration).",
        ),
    ]
    for row in new_projects:
        by_proj[row["Project ID"]] = row

    db["Projects"] = sorted(by_proj.values(), key=lambda r: r["Project ID"])

    DB_PATH.write_text(json.dumps(db, indent=2) + "\n")
    print(
        "Updated content:",
        f"{len(new_ench)} new ench rows,",
        f"{len(spells)} spells,",
        f"{len(new_projects)} new projects,",
        "reworked PRJ-0134/0135/0138",
    )


if __name__ == "__main__":
    main()
