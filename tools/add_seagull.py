"""Adds the Seagull encounter to the content database.

A seagull turns up instead of a pirate one roll in five, and instead of a fish
one roll in twenty. Both pools already total 100 weight, so the weights below
are the percentages the design asked for.
"""

import json
from pathlib import Path

# app_flutter/content symlinks here, so there is only one file to write.
DATABASE = Path("content/data/game-database.json")

SEAGULL_ENEMY = {
    "Enemy ID": "ENM-0021",
    "Internal Key": "seagull",
    "Display Name": "Seagull",
    "Location ID": "LOC-0004",
    "Combat Level": 2,
    "Maximum HP": 100,
    "Min Damage": 20,
    "Max Damage": 40,
    "Combat XP": 900,
    "Minimum Gold": 0,
    "Maximum Gold": 0,
    "Drop Chance": 0,
    "Reward Table ID": None,
    "Status": "Planned",
    "Release Phase": "Launch",
    "Sprite Asset Key": None,
    "Notes": "Dock nuisance. Interrupts the pirates and the fishing. No item drops.",
}

SEAGULL_ACTION = {
    "Action ID": "ACN-0173",
    "Internal Key": "fight_seagull",
    "Display Name": "Fight seagull",
    "Category": "Combat",
    "Relevant Skill ID": "SKL-0001",
    "Target Type": "Enemy",
    "Target ID": "ENM-0021",
    "Proficiency Level": None,
    "Base Duration Seconds": None,
    "XP Reward": 900,
    "Guaranteed Gold": None,
    "Drop Chance": 0,
    "Reward Table ID": None,
    "Secondary Drop Chance": None,
    "Secondary Reward Table ID": None,
    "Status": "Planned",
    "Release Phase": "Launch",
    "Notes": "Combat is resolved in four-second rounds; Enemy record owns HP, damage, and guaranteed Gold.",
}

# Pool weights after the seagull takes its share.
REWEIGHT = {
    "POOL-0018": {"ACN-0091": 80},
    "POOL-0004": {"ACN-0100": 43, "ACN-0101": 28, "ACN-0102": 19, "ACN-0103": 5},
}

NEW_ENTRIES = [
    {
        "Pool Entry ID": "PEN-0065",
        "Pool ID": "POOL-0018",
        "Action ID": "ACN-0173",
        "Weight": 20,
        "Status": "Planned",
        "Notes": "A seagull turns up instead of the pirates one roll in five.",
    },
    {
        "Pool Entry ID": "PEN-0066",
        "Pool ID": "POOL-0004",
        "Action ID": "ACN-0173",
        "Weight": 5,
        "Status": "Planned",
        "Notes": "A seagull turns up instead of a catch one roll in twenty.",
    },
]


def apply(db):
    if any(row["Enemy ID"] == SEAGULL_ENEMY["Enemy ID"] for row in db["Enemies"]):
        raise SystemExit(f"{SEAGULL_ENEMY['Enemy ID']} is already in the database.")
    db["Enemies"].append(SEAGULL_ENEMY)
    db["Actions"].append(SEAGULL_ACTION)

    for entry in db["PoolEntries"]:
        weights = REWEIGHT.get(entry["Pool ID"])
        if weights and entry["Action ID"] in weights:
            entry["Weight"] = weights[entry["Action ID"]]

    last = max(
        index for index, row in enumerate(db["PoolEntries"]) if row["Pool ID"] in REWEIGHT
    )
    db["PoolEntries"][last + 1 : last + 1] = NEW_ENTRIES

    for pool in REWEIGHT:
        total = sum(e["Weight"] for e in db["PoolEntries"] if e["Pool ID"] == pool)
        if total != 100:
            raise SystemExit(f"{pool} weights total {total}, not 100.")
    return db


raw = DATABASE.read_text()
text = json.dumps(apply(json.loads(raw)), indent=2, ensure_ascii=False)
DATABASE.write_text(text + ("\n" if raw.endswith("\n") else ""))
print(f"updated {DATABASE}")
