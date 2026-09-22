#!/usr/bin/env python3
"""Patch Launch content for squid 70, soup stock, and stew XP."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATHS = [
    ROOT / "content/data/game-database.json",
    ROOT / "app_flutter/content/data/game-database.json",
]

SOUP_STOCK_ITEM = "ITEM-0364"
SOUP_STOCK_RECIPE = "RCP-0068"
SOUP_STOCK_ACTION = "ACN-0198"
WATER_ITEM = "ITEM-0365"
KITCHEN_SCRAPS_ITEM = "ITEM-0366"

STEW_RECIPES = {
    "RCP-0012": 1633 * 2,
    "RCP-0013": 2083 * 2,
    "RCP-0060": 5333 * 2,
    "RCP-0063": 1156 * 2,
    "RCP-0064": 1680 * 2,
    "RCP-0065": 2108 * 2,
    "RCP-0066": 2667 * 2,
}


def patch(db: dict) -> None:
    for action in db["Actions"]:
        if action["Action ID"] == "ACN-0104":
            action["Proficiency Level"] = 70
        if action["Action ID"] == "ACN-0127":
            action["Status"] = "Needs Data"
            action["Notes"] = "Unused leftover. Replaced by Squid Noodle Soup."

    for recipe in db["Recipes"]:
        if recipe["Recipe ID"] == "RCP-0044":
            recipe["Status"] = "Needs Data"
            recipe["Notes"] = "Unused leftover. Replaced by Squid Noodle Soup."
        if recipe["Recipe ID"] in STEW_RECIPES:
            recipe["XP Reward"] = STEW_RECIPES[recipe["Recipe ID"]]
            recipe["Ingredient 4 Item ID"] = SOUP_STOCK_ITEM
            recipe["Ingredient 4 Quantity"] = 1

    for item in db["Items"]:
        if item["Item ID"] == "ITEM-0192":
            item["Notes"] = "Unused leftover cook. Existing copies migrate to Squid Noodle Soup."
        if item["Item ID"] == SOUP_STOCK_ITEM:
            item["Notes"] = (
                "Water + kitchen scraps. Infinite on-hand in a kitchen. Cooking 16. 12 seconds. No XP."
            )

    for recipe in db["Recipes"]:
        if recipe["Recipe ID"] == SOUP_STOCK_RECIPE:
            recipe["Notes"] = (
                "Water + kitchen scraps. Infinite on-hand in a kitchen. Used in all stews and soups."
            )
            recipe["Ingredient 1 Item ID"] = WATER_ITEM
            recipe["Ingredient 1 Quantity"] = 1
            recipe["Ingredient 2 Item ID"] = KITCHEN_SCRAPS_ITEM
            recipe["Ingredient 2 Quantity"] = 1

    for action in db["Actions"]:
        if action["Action ID"] == SOUP_STOCK_ACTION:
            action["Notes"] = (
                "Production is hard-gated by Proficiency Level. Water + kitchen scraps, infinite in a kitchen."
            )

    if not any(item["Item ID"] == WATER_ITEM for item in db["Items"]):
        db["Items"].append(
            {
                "Item ID": WATER_ITEM,
                "Internal Key": "water",
                "Display Name": "Water",
                "Category": "Ingredient",
                "Subtype": "Cooking ingredient",
                "Associated Skill ID": "SKL-0007",
                "Equipment Slot ID": None,
                "Functional / Source Tags": "cooking_input; kitchen_ambient",
                "Status": "Planned",
                "Release Phase": "Launch",
                "Description": "Fresh water from the kitchen tap.",
                "Icon Asset Key": "water",
                "Notes": "Ambient kitchen ingredient. Infinite on-hand at a kitchen. Never consumed.",
                "Base Sell Value": 0,
                "Stackable": None,
            }
        )

    if not any(item["Item ID"] == KITCHEN_SCRAPS_ITEM for item in db["Items"]):
        db["Items"].append(
            {
                "Item ID": KITCHEN_SCRAPS_ITEM,
                "Internal Key": "kitchen_scraps",
                "Display Name": "Kitchen Scraps",
                "Category": "Ingredient",
                "Subtype": "Cooking ingredient",
                "Associated Skill ID": "SKL-0007",
                "Equipment Slot ID": None,
                "Functional / Source Tags": "cooking_input; kitchen_ambient",
                "Status": "Planned",
                "Release Phase": "Launch",
                "Description": "Trimmings and leftover bits from the kitchen board.",
                "Icon Asset Key": "kitchen_scraps",
                "Notes": "Ambient kitchen ingredient. Infinite on-hand at a kitchen. Never consumed.",
                "Base Sell Value": 0,
                "Stackable": None,
            }
        )

    if not any(item["Item ID"] == SOUP_STOCK_ITEM for item in db["Items"]):
        db["Items"].append(
            {
                "Item ID": SOUP_STOCK_ITEM,
                "Internal Key": "soup_stock",
                "Display Name": "Soup Stock",
                "Category": "Ingredient",
                "Subtype": "Cooking ingredient",
                "Associated Skill ID": "SKL-0007",
                "Equipment Slot ID": None,
                "Functional / Source Tags": "cooking_output; cooking_input",
                "Status": "Planned",
                "Release Phase": "Launch",
                "Description": "Plain kitchen stock. Used in every stew and soup.",
                "Icon Asset Key": "soup_stock",
                "Notes": "Water + kitchen scraps. Infinite on-hand in a kitchen. Cooking 16. 12 seconds. No XP.",
                "Base Sell Value": 1,
                "Stackable": None,
            }
        )

    if not any(recipe["Recipe ID"] == SOUP_STOCK_RECIPE for recipe in db["Recipes"]):
        db["Recipes"].append(
            {
                "Recipe ID": SOUP_STOCK_RECIPE,
                "Internal Key": "cook_soup_stock",
                "Display Name": "Soup Stock",
                "Skill ID": "SKL-0007",
                "Output Item ID": SOUP_STOCK_ITEM,
                "Output Quantity": 1,
                "Facility ID": "FAC-0001",
                "Proficiency Level": 16,
                "Base Duration Seconds": 12,
                "XP Reward": 0,
                "Knowledge Source": "Automatic level unlock",
                "Action ID": SOUP_STOCK_ACTION,
                "Status": "Planned",
                "Release Phase": "Launch",
                "Notes": "Water + kitchen scraps. Infinite on-hand in a kitchen. Used in all stews and soups.",
                "Ingredient 1 Item ID": "ITEM-0365",
                "Ingredient 1 Quantity": 1,
                "Ingredient 2 Item ID": "ITEM-0366",
                "Ingredient 2 Quantity": 1,
                "Ingredient 3 Item ID": None,
                "Ingredient 3 Quantity": None,
                "Ingredient 4 Item ID": None,
                "Ingredient 4 Quantity": None,
            }
        )

    if not any(action["Action ID"] == SOUP_STOCK_ACTION for action in db["Actions"]):
        db["Actions"].append(
            {
                "Action ID": SOUP_STOCK_ACTION,
                "Internal Key": "cook_soup_stock",
                "Display Name": "Soup Stock",
                "Category": "Standard Production",
                "Relevant Skill ID": "SKL-0007",
                "Target Type": "Item",
                "Target ID": SOUP_STOCK_ITEM,
                "Proficiency Level": 16,
                "Base Duration Seconds": 12,
                "XP Reward": 0,
                "Guaranteed Gold": 0,
                "Drop Chance": 100,
                "Reward Table ID": None,
                "Secondary Drop Chance": None,
                "Secondary Reward Table ID": None,
                "Status": "Planned",
                "Release Phase": "Launch",
                "Notes": "Production is hard-gated by Proficiency Level. Water + kitchen scraps, infinite in a kitchen.",
            }
        )


def main() -> None:
    raw = PATHS[0].read_text()
    db = json.loads(raw)
    patch(db)
    text = json.dumps(db, indent=2, ensure_ascii=False) + "\n"
    for path in PATHS:
        path.write_text(text)
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
