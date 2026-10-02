#!/usr/bin/env python3
"""Retune action timing, gathering primary drops, and combat round config."""

from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "content" / "data" / "game-database.json"

TARGET_DURATION = 12


def scale_xp(old_xp: float | int | None, old_duration: float) -> int | float | None:
    if old_xp is None:
        return None
    if not isinstance(old_xp, (int, float)) or old_duration <= 0:
        return old_xp
    if old_xp == 0:
        return 0
    # Round up to preserve XP/hour after shortening duration.
    return int(math.ceil(old_xp * (TARGET_DURATION / old_duration)))


def patch_timed_rows(rows: list[dict], label: str) -> tuple[int, int]:
    duration_hits = 0
    xp_hits = 0
    for row in rows:
        duration = row.get("Base Duration Seconds")
        if not isinstance(duration, (int, float)) or duration <= 0:
            continue
        if duration != TARGET_DURATION:
            row["XP Reward"] = scale_xp(row.get("XP Reward"), duration)
            row["Base Duration Seconds"] = TARGET_DURATION
            duration_hits += 1
            xp_hits += 1
        elif isinstance(row.get("XP Reward"), float) and not float(row["XP Reward"]).is_integer():
            # Already 12s; still normalize fractional XP upward if any.
            row["XP Reward"] = int(math.ceil(row["XP Reward"]))
            xp_hits += 1
    print(f"{label}: set {duration_hits} durations to {TARGET_DURATION}s (xp scaled on those rows)")
    return duration_hits, xp_hits


def patch_gathering_primary_drops(actions: list[dict]) -> int:
    hits = 0
    for row in actions:
        if row.get("Category") != "Gathering":
            continue
        chance = row.get("Drop Chance")
        if not isinstance(chance, (int, float)) or chance <= 0:
            continue
        row["Drop Chance"] = min(100, chance * 1.5)
        hits += 1
    print(f"Gathering primary Drop Chance ×1.5 on {hits} actions (capped at 100)")
    return hits


def patch_combat_config(config: list[dict]) -> None:
    found = False
    for row in config:
        if row.get("Key") == "combat_round_duration":
            row["Value"] = 6
            row["Notes"] = (
                "Combat round length. Player swing at combat_player_attack_at; "
                "enemy swing at round end; auto-eat uses combat_eat_between_seconds."
            )
            found = True
            break
    if not found:
        raise SystemExit("combat_round_duration config row missing")

    extras = {
        "combat_player_attack_at": (
            5,
            "seconds",
            "Seconds into a combat round when the player's attack resolves.",
        ),
        "combat_enemy_attack_at": (
            6,
            "seconds",
            "Seconds into a combat round when the enemy's attack resolves (round end).",
        ),
        "combat_eat_between_seconds": (
            1,
            "seconds",
            "Auto-eat delay inserted between combat rounds and between actions after a kill.",
        ),
    }
    by_key = {row.get("Key"): row for row in config}
    for key, (value, unit, notes) in extras.items():
        if key in by_key:
            by_key[key]["Value"] = value
            by_key[key]["Unit"] = unit
            by_key[key]["Notes"] = notes
        else:
            # Insert after combat_round_duration.
            idx = next(i for i, row in enumerate(config) if row.get("Key") == "combat_round_duration")
            config.insert(
                idx + 1,
                {"Key": key, "Value": value, "Unit": unit, "Notes": notes},
            )
    print("Combat config: round=6s, player@5s, enemy@6s, eat between=1s")


def main() -> None:
    db = json.loads(DB_PATH.read_text())
    patch_timed_rows(db["Actions"], "Actions")
    patch_timed_rows(db["Recipes"], "Recipes")
    patch_gathering_primary_drops(db["Actions"])
    patch_combat_config(db["Config"])
    DB_PATH.write_text(json.dumps(db, indent=2, ensure_ascii=True) + "\n")
    print(f"Wrote {DB_PATH}")


if __name__ == "__main__":
    main()
