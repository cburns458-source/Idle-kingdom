#!/usr/bin/env python3
"""Content pass: botany patches, thievery remap, seed shop, lockpicks, dialogue."""
from __future__ import annotations

import json
from copy import deepcopy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "content/data/game-database.json"

SEED_SECONDS = 3 * 60 * 60
SAPLING_SECONDS = 12 * 60 * 60

# Kept botany plantables: level, output item, kind
SEEDS = {
    "ITEM-0324": {"name": "Potato Seed", "key": "potato_seed", "level": 1, "output": "ITEM-0025", "kind": "seed"},
    "ITEM-0339": {"name": "Carrot Seed", "key": "carrot_seed", "level": 10, "output": "ITEM-0027", "kind": "seed"},
    "ITEM-0333": {"name": "Fernleaf Seed", "key": "fernleaf_seed", "level": 15, "output": "ITEM-0031", "kind": "seed"},
    "ITEM-0334": {"name": "Mosstole Seed", "key": "mosstole_seed", "level": 35, "output": "ITEM-0032", "kind": "seed"},
    "ITEM-0340": {"name": "Grape Seed", "key": "grape_seed", "level": 55, "output": "ITEM-0029", "kind": "seed"},
    "ITEM-0336": {"name": "Augur Weed Seed", "key": "augur_weed_seed", "level": 60, "output": "ITEM-0033", "kind": "seed"},
    "ITEM-0337": {"name": "Moonblossom Seed", "key": "moonblossom_seed", "level": 75, "output": "ITEM-0207", "kind": "seed"},
}
SAPLINGS = {
    "ITEM-0326": {"name": "Cedar Sapling", "key": "cedar_sapling", "level": 1, "output": "ITEM-0015", "kind": "sapling"},
    "ITEM-0327": {"name": "Oak Sapling", "key": "oak_sapling", "level": 16, "output": "ITEM-0016", "kind": "sapling"},
    "ITEM-0328": {"name": "Poplar Sapling", "key": "poplar_sapling", "level": 31, "output": "ITEM-0017", "kind": "sapling"},
    "ITEM-0329": {"name": "Maple Sapling", "key": "maple_sapling", "level": 51, "output": "ITEM-0018", "kind": "sapling"},
    "ITEM-0330": {"name": "Mahogany Sapling", "key": "mahogany_sapling", "level": 71, "output": "ITEM-0019", "kind": "sapling"},
}
# Shallows-only kelp plantable (not in citadel shop L1-50 list)
KELP_SPORES = "ITEM-0350"
CUT_SEEDS = {
    "ITEM-0325",  # golden spud seed
    "ITEM-0331",  # ancient sapling
    "ITEM-0332",  # wild root
    "ITEM-0335",  # wild berry
    "ITEM-0338",  # starroot
    "ITEM-0349",  # mushroom spore
}

# Gather action -> kept seed secondary table
SEED_DROP_ACTIONS = {
    "ACN-0035": ("ITEM-0324", "RWT-0129"),  # potato
    "ACN-0162": ("ITEM-0339", "RWT-0141"),  # carrot
    "ACN-0106": ("ITEM-0333", "RWT-0150"),  # fernleaf dedicated
    "ACN-0107": ("ITEM-0334", "RWT-0138"),  # mosstole
    "ACN-0163": ("ITEM-0340", "RWT-0142"),  # grapes
    "ACN-0109": ("ITEM-0336", "RWT-0151"),  # augur dedicated
    "ACN-0110": ("ITEM-0337", "RWT-0139"),  # moonblossom
    "ACN-0046": ("ITEM-0326", "RWT-0131"),  # cedar
    "ACN-0047": ("ITEM-0327", "RWT-0132"),  # oak
    "ACN-0048": ("ITEM-0328", "RWT-0133"),  # poplar
    "ACN-0049": ("ITEM-0329", "RWT-0134"),  # maple
    "ACN-0050": ("ITEM-0330", "RWT-0135"),  # mahogany
    "ACN-0181": ("ITEM-0350", "RWT-0152"),  # kelp spores
}


def xp_for(level: int, kind: str) -> int:
    if kind == "sapling":
        return 120 + level * 25
    return 60 + level * 18


def notes_for(spec: dict) -> str:
    seconds = SAPLING_SECONDS if spec["kind"] == "sapling" else SEED_SECONDS
    tag = "botany_sapling" if spec["kind"] == "sapling" else "botany_seed"
    return (
        f"BotanyPlant; Output:{spec['output']}; GrowSeconds:{seconds}; "
        f"Xp:{xp_for(spec['level'], spec['kind'])}; RequiresLevel:{spec['level']}"
    )


def main() -> None:
    db = json.loads(DB_PATH.read_text())
    items = {i["Item ID"]: i for i in db["Items"]}
    actions = {a["Action ID"]: a for a in db["Actions"]}
    rewards = db["RewardEntries"]
    activities = {a["Activity ID"]: a for a in db["Activities"]}

    # --- Update kept seeds/saplings ---
    for iid, spec in {**SEEDS, **SAPLINGS}.items():
        item = items[iid]
        item["Display Name"] = spec["name"]
        item["Internal Key"] = spec["key"]
        item["Icon Asset Key"] = spec["key"]
        item["Status"] = "Confirmed"
        item["Functional / Source Tags"] = (
            f"botany_{'sapling' if spec['kind'] == 'sapling' else 'seed'}; "
            f"{'woodcutting_related' if spec['kind'] == 'sapling' else 'harvesting_related'}"
        )
        item["Notes"] = notes_for(spec)
        item["Associated Skill ID"] = "SKL-0014"

    # Kelp spores
    if KELP_SPORES not in items:
        db["Items"].append(
            {
                "Item ID": KELP_SPORES,
                "Internal Key": "kelp_spores",
                "Display Name": "Kelp Spores",
                "Category": "Seed",
                "Subtype": "Botany",
                "Associated Skill ID": "SKL-0014",
                "Equipment Slot ID": None,
                "Functional / Source Tags": "botany_seed; shallows_only",
                "Stackable": "Yes",
                "Base Sell Value": 5,
                "Status": "Confirmed",
                "Release Phase": "Launch",
                "Description": "Plant only in The Shallows.",
                "Notes": f"BotanyPlant; Output:ITEM-0342; GrowSeconds:{SEED_SECONDS}; Xp:{xp_for(40, 'seed')}; RequiresLevel:40; ShallowsOnly",
                "Icon Asset Key": "kelp_spores",
                "Rarity": "Common",
            }
        )
        items[KELP_SPORES] = db["Items"][-1]
    else:
        items[KELP_SPORES]["Notes"] = (
            f"BotanyPlant; Output:ITEM-0342; GrowSeconds:{SEED_SECONDS}; "
            f"Xp:{xp_for(40, 'seed')}; RequiresLevel:40; ShallowsOnly"
        )
        items[KELP_SPORES]["Functional / Source Tags"] = "botany_seed; shallows_only"
        items[KELP_SPORES]["Icon Asset Key"] = "kelp_spores"

    # Strip cut seeds
    for iid in CUT_SEEDS:
        if iid not in items:
            continue
        item = items[iid]
        item["Functional / Source Tags"] = "retired_botany"
        item["Status"] = "Planned"
        item["Notes"] = "Retired from Botany planting."
        item["Release Phase"] = "Expansion"

    # --- Lockpicks ITEM-0351 ---
    lock_id = "ITEM-0351"
    if lock_id not in items:
        db["Items"].append(
            {
                "Item ID": lock_id,
                "Internal Key": "lockpicks",
                "Display Name": "Lockpicks",
                "Category": "Tool",
                "Subtype": "Thievery",
                "Associated Skill ID": "SKL-0015",
                "Equipment Slot ID": "SLOT-0001",
                "Functional / Source Tags": "thievery_tool; lockpick; stackable_tool",
                "Stackable": "Yes",
                "Base Sell Value": 8,
                "Status": "Confirmed",
                "Release Phase": "Launch",
                "Description": "Required to crack safes and bank deposit boxes.",
                "Notes": "Consumable tool. Stacks in the Weapon/Tool slot.",
                "Icon Asset Key": "lockpicks",
                "Rarity": "Common",
            }
        )
    # Equipment row for tool slot stacking if needed
    eq_ids = {e.get("Item ID") for e in db["Equipment"]}
    if lock_id not in eq_ids:
        sample = next(e for e in db["Equipment"] if e.get("Slot ID") == "SLOT-0001")
        existing_eq_nums = [
            int(str(e["Equipment ID"]).split("-")[1])
            for e in db["Equipment"]
            if isinstance(e.get("Equipment ID"), str) and str(e["Equipment ID"]).startswith("EQP-")
        ]
        next_eq = f"EQP-{max(existing_eq_nums, default=0) + 1:04d}"
        row = {k: None for k in sample.keys()}
        row.update(
            {
                "Equipment ID": next_eq,
                "Item ID": lock_id,
                "Slot ID": "SLOT-0001",
                "Internal Key": "lockpicks",
                "Display Name": "Lockpicks",
                "Status": "Confirmed",
                "Release Phase": "Launch",
                "Min Damage": 0,
                "Max Damage": 0,
                "Notes": "Stackable thievery tool.",
            }
        )
        db["Equipment"].append(row)

    # Recipe + action for lockpicks
    recipe_id = "RCP-0062"
    action_craft = "ACN-0189"
    if not any(r["Recipe ID"] == recipe_id for r in db["Recipes"]):
        db["Recipes"].append(
            {
                "Recipe ID": recipe_id,
                "Internal Key": "craft_lockpicks",
                "Display Name": "Lockpicks",
                "Skill ID": "SKL-0009",
                "Output Item ID": lock_id,
                "Output Quantity": 20,
                "Facility ID": "FAC-0003",
                "Proficiency Level": 20,
                "Base Duration Seconds": 12,
                "XP Reward": 80,
                "Knowledge Source": "Auto",
                "Action ID": action_craft,
                "Ingredient 1 Item ID": "ITEM-0076",
                "Ingredient 1 Quantity": 1,
                "Ingredient 2 Item ID": None,
                "Ingredient 2 Quantity": None,
                "Ingredient 3 Item ID": None,
                "Ingredient 3 Quantity": None,
                "Ingredient 4 Item ID": None,
                "Ingredient 4 Quantity": None,
                "Status": "Confirmed",
                "Release Phase": "Launch",
                "Notes": "1 iron bar makes 20 lockpicks.",
            }
        )
    if action_craft not in actions:
        db["Actions"].append(
            {
                "Action ID": action_craft,
                "Internal Key": "craft_lockpicks",
                "Display Name": "Craft lockpicks",
                "Category": "Production",
                "Relevant Skill ID": "SKL-0009",
                "Target Type": "Item",
                "Target ID": lock_id,
                "Proficiency Level": 20,
                "Base Duration Seconds": 12,
                "XP Reward": 80,
                "Guaranteed Gold": 0,
                "Drop Chance": 100,
                "Reward Table ID": None,
                "Secondary Drop Chance": None,
                "Secondary Reward Table ID": None,
                "Status": "Confirmed",
                "Release Phase": "Launch",
                "Notes": "Crafting Workshop.",
            }
        )
        actions[action_craft] = db["Actions"][-1]

    # --- Seed secondary drops at 1% ---
    # Clear old seed secondaries on cut/irrelevant actions
    clear_secondary = [
        "ACN-0036",
        "ACN-0051",
        "ACN-0105",
        "ACN-0108",
        "ACN-0111",
        "ACN-0184",
    ]
    for aid in clear_secondary:
        if aid in actions:
            actions[aid]["Secondary Drop Chance"] = None
            actions[aid]["Secondary Reward Table ID"] = None

    # Fernleaf/augur previously shared RWT-0120 — give dedicated 1% tables
    def ensure_seed_table(table_id: str, item_id: str, name: str) -> None:
        existing = [e for e in rewards if e.get("Reward Table ID") == table_id]
        if existing:
            for e in existing:
                if e.get("Reward Type") == "Item":
                    e["Reward ID / Value"] = item_id
                    e["Weight"] = 100
                    e["Minimum Quantity"] = 1
                    e["Maximum Quantity"] = 1
                    e["Status"] = "Confirmed"
            return
        rewards.append(
            {
                "Reward Entry ID": f"RWE-{9000 + len(rewards)}",
                "Reward Table ID": table_id,
                "Reward Table Name": name,
                "Purpose": "Botany seed secondary",
                "Reward Type": "Item",
                "Reward ID / Value": item_id,
                "Weight": 100,
                "Minimum Quantity": 1,
                "Maximum Quantity": 1,
                "Skill ID": None,
                "XP Amount": None,
                "Status": "Confirmed",
                "Notes": "1% seed/sapling drop",
            }
        )

    for aid, (seed_id, table_id) in SEED_DROP_ACTIONS.items():
        ensure_seed_table(table_id, seed_id, f"Botany seed {seed_id}")
        if aid in actions:
            actions[aid]["Secondary Drop Chance"] = 1
            actions[aid]["Secondary Reward Table ID"] = table_id

    # Strip fernleaf/berry/augur from shared RWT-0120 seed sides
    for e in list(rewards):
        if e.get("Reward Table ID") == "RWT-0120" and str(e.get("Reward ID / Value", "")).startswith(
            "ITEM-033"
        ):
            if e.get("Reward ID / Value") in ("ITEM-0333", "ITEM-0335", "ITEM-0336"):
                rewards.remove(e)

    # Hide golden spud harvest from players (action exists but mystery)
    if "ACN-0036" in actions:
        actions["ACN-0036"]["Notes"] = (
            (actions["ACN-0036"].get("Notes") or "") + "; HideFromCodex; MysteryDrop"
        ).strip("; ")
        actions["ACN-0036"]["Status"] = "Planned"
        actions["ACN-0036"]["Release Phase"] = "Expansion"

    # --- Remap Thievery actions ---
    # Reuse ACN-0185..0188 and add ACN-0190, ACN-0191
    thievery_defs = [
        {
            "id": "ACN-0185",
            "key": "steal_general_store",
            "name": "Steal from the general store",
            "level": 1,
            "duration": 20,
            "xp": 400,
            "fail": 30,
            "notes": "ThieverySteal; FailChance:30; FailDamagePercent:10",
            "table": "RWT-0125",
            "act": "ACT-0054",
            "pool": "POOL-0042",
            "loc": "LOC-0024",
            "ctx": "Steal from the general store",
            "desc": "Lift wooden tools from the shelves when no one is looking.",
        },
        {
            "id": "ACN-0186",
            "key": "steal_barracks",
            "name": "Steal from the barracks",
            "level": 10,
            "duration": 25,
            "xp": 700,
            "fail": 35,
            "notes": "ThieverySteal; FailChance:35; FailDamagePercent:10",
            "table": "RWT-0126",
            "act": "ACT-0055",
            "pool": "POOL-0043",
            "loc": "LOC-0017",
            "ctx": "Steal from the barracks",
            "desc": "Slip iron swords from the Castle Barracks racks.",
        },
        {
            "id": "ACN-0190",
            "key": "steal_goblins",
            "name": "Steal from goblins",
            "level": 25,
            "duration": 22,
            "xp": 900,
            "fail": 40,
            "notes": "ThieverySteal; FailChance:40; FailDamagePercent:10",
            "table": "RWT-0153",
            "act": "ACT-0058",
            "pool": "POOL-0046",
            "loc": "LOC-0003",
            "ctx": "Steal from goblins",
            "desc": "Pick through goblin packs for trout or a few coins.",
        },
        {
            "id": "ACN-0188",
            "key": "steal_kitchen",
            "name": "Steal from the kitchen",
            "level": 30,
            "duration": 15,
            "xp": 800,
            "fail": None,
            "notes": "ThieverySteal; NoConsequences",
            "table": "RWT-0128",
            "act": "ACT-0057",
            "pool": "POOL-0045",
            "loc": "LOC-0023",
            "ctx": "Steal from the kitchen",
            "desc": "Swipe low cooked food from the steel. No one notices.",
        },
        {
            "id": "ACN-0187",
            "key": "pick_safe_kings",
            "name": "Pick the king's safe",
            "level": 45,
            "duration": 40,
            "xp": 1600,
            "fail": 45,
            "notes": "ThieveryLockpick; RequiresLockpick; FailChance:45; FailDamagePercent:10",
            "table": "RWT-0127",
            "act": "ACT-0056",
            "pool": "POOL-0044",
            "loc": "LOC-0016",
            "ctx": "Pick the king's safe",
            "desc": "Work the safe in the King's Quarters. Needs lockpicks.",
        },
        {
            "id": "ACN-0191",
            "key": "pick_deposit_box",
            "name": "Pick a deposit box",
            "level": 50,
            "duration": 45,
            "xp": 2000,
            "fail": 50,
            "notes": "ThieveryLockpick; RequiresLockpick; BankThievery; FailChance:50; FailDamagePercent:10",
            "table": "RWT-0154",
            "act": "ACT-0059",
            "pool": "POOL-0047",
            "loc": "LOC-0034",  # Town Bank; Citadel mirrored below
            "ctx": "Pick a deposit box",
            "desc": "Crack a bank deposit box for mid gathering goods. Needs lockpicks.",
        },
    ]

    def upsert_action(defn: dict) -> None:
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
            actions[defn["id"]] = row

    def upsert_activity(defn: dict, loc: str, act_id: str | None = None) -> None:
        aid = act_id or defn["act"]
        row = {
            "Activity ID": aid,
            "Internal Key": defn["key"] if act_id is None else f"{defn['key']}_{loc.lower()}",
            "Contextual Name": defn["ctx"],
            "Location ID": loc,
            "Description": defn["desc"],
            "Danger Warning Combat Level": None,
            "Pool ID": defn["pool"],
            "Pool Internal Key": defn["key"],
            "Status": "Confirmed",
            "Release Phase": "Launch",
            "Notes": None,
        }
        existing = next((a for a in db["Activities"] if a["Activity ID"] == aid), None)
        if existing:
            existing.update(row)
        else:
            db["Activities"].append(row)

    def upsert_pool_entry(pool: str, action_id: str, pen: str) -> None:
        existing = next((p for p in db["PoolEntries"] if p["Pool Entry ID"] == pen), None)
        row = {
            "Pool Entry ID": pen,
            "Pool ID": pool,
            "Action ID": action_id,
            "Weight": 100,
            "Status": "Confirmed",
            "Notes": None,
        }
        if existing:
            existing.update(row)
        else:
            db["PoolEntries"].append(row)

    pen_map = {
        "ACN-0185": "PEN-0096",
        "ACN-0186": "PEN-0097",
        "ACN-0187": "PEN-0098",
        "ACN-0188": "PEN-0099",
        "ACN-0190": "PEN-0100",
        "ACN-0191": "PEN-0101",
    }
    for defn in thievery_defs:
        upsert_action(defn)
        upsert_activity(defn, defn["loc"])
        upsert_pool_entry(defn["pool"], defn["id"], pen_map[defn["id"]])

    # Second bank activity for deposit box
    deposit = next(d for d in thievery_defs if d["id"] == "ACN-0191")
    upsert_activity(deposit, "LOC-0035", act_id="ACT-0060")

    # Reward tables
    def set_table(table_id: str, entries: list[dict], name: str) -> None:
        # remove old entries for table
        keep = [e for e in rewards if e.get("Reward Table ID") != table_id]
        rewards[:] = keep
        for i, ent in enumerate(entries):
            rewards.append(
                {
                    "Reward Entry ID": f"RWE-T{table_id[-4:]}{i}",
                    "Reward Table ID": table_id,
                    "Reward Table Name": name,
                    "Purpose": "Primary output",
                    "Reward Type": ent["type"],
                    "Reward ID / Value": ent["id"],
                    "Weight": ent["weight"],
                    "Minimum Quantity": ent.get("min", 1),
                    "Maximum Quantity": ent.get("max", 1),
                    "Skill ID": None,
                    "XP Amount": None,
                    "Status": "Confirmed",
                    "Notes": ent.get("notes"),
                }
            )

    set_table(
        "RWT-0125",
        [
            {"type": "Item", "id": "ITEM-0100", "weight": 25},
            {"type": "Item", "id": "ITEM-0101", "weight": 25},
            {"type": "Item", "id": "ITEM-0102", "weight": 25},
            {"type": "Item", "id": "ITEM-0103", "weight": 25},
        ],
        "General Store Steal",
    )
    set_table(
        "RWT-0126",
        [{"type": "Item", "id": "ITEM-0128", "weight": 100}],
        "Barracks Steal",
    )
    set_table(
        "RWT-0153",
        [
            {"type": "Item", "id": "ITEM-0048", "weight": 50, "notes": "Raw trout"},
            {"type": "Gold", "id": "5", "weight": 50, "notes": "5 gold"},
        ],
        "Goblin Steal",
    )
    # Low cooked foods
    cooked = ["ITEM-0058", "ITEM-0059"]
    # add more cooked if present
    for i in db["Items"]:
        if i.get("Category") == "Food" and "Cooked" in str(i.get("Display Name", "")):
            if i["Item ID"] not in cooked:
                cooked.append(i["Item ID"])
        if i["Item ID"] in ("ITEM-0060", "ITEM-0061", "ITEM-0062"):
            cooked.append(i["Item ID"])
    cooked = list(dict.fromkeys(cooked))[:6]
    set_table(
        "RWT-0128",
        [{"type": "Item", "id": cid, "weight": 100 // len(cooked) or 1} for cid in cooked],
        "Kitchen Steal",
    )
    # Fix kitchen weights to sum nicely
    set_table(
        "RWT-0128",
        [{"type": "Item", "id": cid, "weight": 10} for cid in cooked],
        "Kitchen Steal",
    )
    set_table(
        "RWT-0127",
        [
            {"type": "Item", "id": "ITEM-0012", "weight": 10, "notes": "Sapphire 10%"},
            {"type": "Gold", "id": "25", "weight": 90, "notes": "25 gold 90%"},
        ],
        "King Safe",
    )
    mid_items = [
        "ITEM-0005",
        "ITEM-0032",
        "ITEM-0049",
        "ITEM-0017",
        "ITEM-0028",
        "ITEM-0006",
        "ITEM-0029",
        "ITEM-0050",
        "ITEM-0018",
        "ITEM-0033",
    ]
    set_table(
        "RWT-0154",
        [{"type": "Item", "id": mid, "weight": 10} for mid in mid_items],
        "Deposit Box",
    )

    # --- Citadel seed shop SHP-0009 at LOC-0029 ---
    shop_items = []
    # seeds/saplings level <= 50
    for iid, spec in {**SEEDS, **SAPLINGS}.items():
        if spec["level"] <= 50:
            shop_items.append((iid, 100 if spec["kind"] == "seed" else 10))
    shop = {
        "Shop ID": "SHP-0009",
        "Internal Key": "citadel_seed_stall",
        "Display Name": "Seed Stall",
        "Location ID": "LOC-0029",
        "Shop Type": "Specialist",
        "Status": "Confirmed",
        "Release Phase": "Launch",
        "Description": "Sells Botany seeds and saplings through level 50.",
        "Notes": "Seeds stock 100. Saplings stock 10.",
    }
    for i in range(1, 21):
        shop[f"Entry {i} Item ID"] = None
        shop[f"Entry {i} Mode"] = None
        shop[f"Entry {i} Price"] = None
        shop[f"Entry {i} Currency ID"] = None
        shop[f"Entry {i} Daily Limit"] = None
    for idx, (iid, stock) in enumerate(shop_items, start=1):
        shop[f"Entry {idx} Item ID"] = iid
        shop[f"Entry {idx} Mode"] = "Sell"
        shop[f"Entry {idx} Price"] = None
        shop[f"Entry {idx} Currency ID"] = "CUR-0001"
        shop[f"Entry {idx} Daily Limit"] = stock
    existing_shop = next((s for s in db["Shops"] if s["Shop ID"] == "SHP-0009"), None)
    if existing_shop:
        existing_shop.update(shop)
    else:
        db["Shops"].append(shop)

    # --- Grand Feast courtyard mention ---
    q1 = next(q for q in db["Quests"] if q["Quest ID"] == "QST-0001")
    q1["Possible Rewards"] = (
        "10,000 Cooking XP; Golden Spud x1; Unlocks the Courtyard Botany plot"
    )
    q1["Notes"] = "Non-repeatable Launch quest. Completing unlocks the Courtyard Botany plot."
    # Add/replace farewell dialogue
    dialogues = db["QuestDialogue"]
    farewell = next(
        (d for d in dialogues if d.get("Dialogue ID") == "QDL-0024"),
        None,
    )
    line = (
        "The kitchens will sing again — and for your work, the Courtyard plot is yours. "
        "Plant what you find beyond these walls, and let Restoria grow with you."
    )
    if farewell:
        farewell["Line"] = line
        farewell["Quest ID"] = "QST-0001"
        farewell["NPC ID"] = "NPC-0001"
        farewell["Notes"] = "When: completed; unlocks Courtyard Botany plot."
    else:
        dialogues.append(
            {
                "Dialogue ID": "QDL-0024",
                "Quest ID": "QST-0001",
                "NPC ID": "NPC-0001",
                "Line": line,
                "Status": "Confirmed",
                "Release Phase": "Launch",
                "Notes": "When: completed; unlocks Courtyard Botany plot.",
            }
        )
    # Helge Going Deeper completion (must keep When: completed so completedNote works)
    helge_farewell = next((d for d in dialogues if d.get("Dialogue ID") == "QDL-0020"), None)
    if helge_farewell and helge_farewell.get("Quest ID") == "QST-0008":
        helge_farewell["Notes"] = "When: completed"

    # --- First Planting botany intro dialogue ---
    q11 = next(q for q in db["Quests"] if q["Quest ID"] == "QST-0011")
    q11["Pitch"] = (
        "You've got a seed in that pack. Bring me a potato from the field and I'll show you "
        "how Restoria's plots work — Botany, patient as the seasons."
    )
    q11["Summary"] = "Fennel introduces Botany after you find a seed."
    q11["Status"] = "Confirmed"
    botany_lines = [
        (
            "QDL-0021",
            "A seed is a promise. The Courtyard plot opens once the King's feast is settled — "
            "until then, gather well and keep what sprouts.",
        ),
        (
            "QDL-0022",
            "Plant seeds in threes or a single sapling, never both. Tend the timer, then harvest. "
            "Half the time the plot gives your planting back, with a handful of the crop besides.",
        ),
        (
            "QDL-0023",
            "Go on then — Botany rewards those who wait. I'll be here when your first harvest comes in.",
        ),
    ]
    for did, text in botany_lines:
        existing = next((d for d in dialogues if d.get("Dialogue ID") == did), None)
        row = {
            "Dialogue ID": did,
            "Quest ID": "QST-0011",
            "NPC ID": "NPC-0014",
            "Line": text,
            "Status": "Confirmed",
            "Release Phase": "Launch",
            "Notes": "First Planting Botany intro.",
        }
        if existing:
            existing.update(row)
        else:
            dialogues.append(row)

    # Confirm skills
    for sid in ("SKL-0014", "SKL-0015"):
        sk = next(s for s in db["Skills"] if s["Skill ID"] == sid)
        sk["Status"] = "Confirmed"

    DB_PATH.write_text(json.dumps(db, separators=(",", ":"), ensure_ascii=False) + "\n")
    # Mirror if separate
    mirror = ROOT / "app_flutter/content/data/game-database.json"
    if mirror.exists() and mirror.resolve() != DB_PATH.resolve():
        mirror.write_text(DB_PATH.read_text())
    print("patched", DB_PATH)


if __name__ == "__main__":
    main()
