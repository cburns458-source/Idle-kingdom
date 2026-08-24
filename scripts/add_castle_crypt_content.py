#!/usr/bin/env python3
"""Insert Castle Crypt, Mage's Wand, and dragon-boss notes into the database."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATABASE = ROOT / 'content/data/game-database.json'


def main() -> None:
    db = json.loads(DATABASE.read_text())

    locations = db['Locations']
    if not any(row['Location ID'] == 'LOC-0037' for row in locations):
        locations.append(
            {
                'Location ID': 'LOC-0037',
                'Internal Key': 'castle_crypt',
                'Display Name': 'Castle Crypt',
                'Map ID': 'MAP-0003',
                'Location Type': 'Combat Area',
                'Parent Location ID': 'LOC-0013',
                'Node ID': 'NODE-0037',
                'Status': 'Planned',
                'Release Phase': 'Launch',
                'Description': 'A low stone vault under the castle, where the old spirits still walk.',
                'Danger / Hostility': 'The old spirits still linger.',
                'Background Asset Key': None,
                'Map Node Name': None,
                'Hidden On Map IDs': None,
                'Notes': 'Castle sub-map. Fend off the old spirits, or try the sealed catacombs.',
                'Landing Location ID': None,
            }
        )

    connections = db['TravelConnections']
    if not any(row['Connection ID'] == 'TRV-0020' for row in connections):
        connections.append(
            {
                'Connection ID': 'TRV-0020',
                'From Location ID': 'LOC-0013',
                'To Location ID': 'LOC-0037',
                'Method': 'Castle sub-map',
                'Direction': 'Two-way',
                'Base Duration': None,
                'Required Mount / Status': None,
                'Status': 'Planned',
                'Release Phase': 'Launch',
                'Notes': 'Castle gateway to Castle Crypt',
            }
        )

    activities = db['Activities']
    if not any(row['Activity ID'] == 'ACT-0041' for row in activities):
        activities.append(
            {
                'Activity ID': 'ACT-0041',
                'Internal Key': 'fend_off_old_spirits',
                'Contextual Name': 'Fend off the old spirits',
                'Location ID': 'LOC-0037',
                'Description': 'Ghost and skeleton Combat in the Castle Crypt.',
                'Danger Warning Combat Level': 34,
                'Pool ID': 'POOL-0031',
                'Pool Internal Key': 'castle_crypt_spirits',
                'Status': 'Planned',
                'Release Phase': 'Launch',
                'Notes': 'Ghost 90%, skeleton 10%. Ghosts drop no gold or items.',
            }
        )
    if not any(row['Activity ID'] == 'ACT-0042' for row in activities):
        activities.append(
            {
                'Activity ID': 'ACT-0042',
                'Internal Key': 'enter_the_catacombs',
                'Contextual Name': 'Enter the catacombs',
                'Location ID': 'LOC-0037',
                'Description': 'The deeper catacombs are sealed for now.',
                'Danger Warning Combat Level': None,
                'Pool ID': None,
                'Pool Internal Key': None,
                'Status': 'Planned',
                'Release Phase': 'Launch',
                'Notes': 'coming_soon',
            }
        )

    entries = db['PoolEntries']
    if not any(row['Pool Entry ID'] == 'PEN-0075' for row in entries):
        entries.append(
            {
                'Pool Entry ID': 'PEN-0075',
                'Pool ID': 'POOL-0031',
                'Action ID': 'ACN-0176',
                'Weight': 90,
                'Status': 'Planned',
                'Notes': 'Fight ghost — 90% of fending off the old spirits.',
            }
        )
    if not any(row['Pool Entry ID'] == 'PEN-0076' for row in entries):
        entries.append(
            {
                'Pool Entry ID': 'PEN-0076',
                'Pool ID': 'POOL-0031',
                'Action ID': 'ACN-0006',
                'Weight': 10,
                'Status': 'Planned',
                'Notes': 'Fight skeleton — 10% of fending off the old spirits.',
            }
        )

    actions = db['Actions']
    if not any(row['Action ID'] == 'ACN-0176' for row in actions):
        actions.append(
            {
                'Action ID': 'ACN-0176',
                'Internal Key': 'fight_ghost',
                'Display Name': 'Fight ghost',
                'Category': 'Combat',
                'Relevant Skill ID': 'SKL-0001',
                'Target Type': 'Enemy',
                'Target ID': 'ENM-0022',
                'Proficiency Level': None,
                'Base Duration Seconds': None,
                'XP Reward': 6000,
                'Guaranteed Gold': None,
                'Drop Chance': 0,
                'Reward Table ID': None,
                'Secondary Drop Chance': None,
                'Secondary Reward Table ID': None,
                'Status': 'Planned',
                'Release Phase': 'Launch',
                'Notes': 'Crypt ghost. Same Combat as a Zombie, but no gold or drops.',
            }
        )

    enemies = db['Enemies']
    for enemy in enemies:
        if enemy['Enemy ID'] == 'ENM-0006':
            enemy['Notes'] = (
                'boss; sleep_start:4; wake_hp_ratio:0.5; rampage_hp_ratio:0.25; respawn_seconds:10'
            )
    if not any(row['Enemy ID'] == 'ENM-0022' for row in enemies):
        enemies.append(
            {
                'Enemy ID': 'ENM-0022',
                'Internal Key': 'ghost',
                'Display Name': 'Ghost',
                'Location ID': 'LOC-0037',
                'Combat Level': 34,
                'Maximum HP': 1300,
                'Min Damage': 80,
                'Max Damage': 160,
                'Combat XP': 6000,
                'Minimum Gold': 0,
                'Maximum Gold': 0,
                'Drop Chance': 0,
                'Reward Table ID': None,
                'Status': 'Planned',
                'Release Phase': 'Launch',
                'Sprite Asset Key': None,
                'Notes': 'Castle Crypt spirit. Zombie Combat, no gold or drops.',
            }
        )

    items = db['Items']
    if not any(row['Item ID'] == 'ITEM-0307' for row in items):
        items.append(
            {
                'Item ID': 'ITEM-0307',
                'Internal Key': 'mages_wand',
                'Display Name': "Mage's Wand",
                'Category': 'Weapon',
                'Subtype': 'Wand',
                'Associated Skill ID': 'SKL-0013',
                'Equipment Slot ID': 'SLOT-0001',
                'Functional / Source Tags': 'combat_weapon; staff_sparks; project_output',
                'Status': 'Planned',
                'Release Phase': 'Launch',
                'Description': 'A maple wand that throws a second spark after each hit.',
                'Icon Asset Key': 'mages_wand',
                'Notes': 'Arcana 55 craft. Equip Arcana 50. One-handed.',
                'Base Sell Value': 720,
            }
        )

    equipment = db['Equipment']
    if not any(row['Equipment ID'] == 'EQP-0185' for row in equipment):
        equipment.append(
            {
                'Equipment ID': 'EQP-0185',
                'Item ID': 'ITEM-0307',
                'Slot ID': 'SLOT-0001',
                'Required Skill ID': 'SKL-0013',
                'Required Level': 50,
                'Secondary Required Skill ID': None,
                'Secondary Required Level': None,
                'Min Damage': 25,
                'Max Damage': 50,
                'HP Bonus': None,
                'Damage Reduction': None,
                'Healing Amount': None,
                'Action Time Reduction %': None,
                'Capabilities / Effects': 'combat_weapon; staff_sparks',
                'Status': 'Planned',
                'Notes': 'One-handed. Second spark hit after the main swing. Spark damage follows Arcana level.',
            }
        )

    projects = db['Projects']
    if not any(row['Project ID'] == 'PRJ-0147' for row in projects):
        projects.append(
            {
                'Project ID': 'PRJ-0147',
                'Internal Key': 'arcana_mages_wand',
                'Display Name': "Mage's Wand",
                'Skill ID': 'SKL-0013',
                'Output Item / Target ID': 'ITEM-0307',
                'Output Quantity': 1,
                'Facility ID': 'FAC-0008',
                'Recipe ID': None,
                'XP Reward': 200000,
                'Gold Cost': 0,
                'Instant': 'Yes',
                'Status': 'Planned',
                'Release Phase': 'Launch',
                'Notes': 'Maple timber, essence, and a cut emerald.',
                'Input 1 Item ID': 'ITEM-0217',
                'Input 1 Quantity': 5,
                'Input 2 Item ID': 'ITEM-0011',
                'Input 2 Quantity': 5,
                'Input 3 Item ID': 'ITEM-0089',
                'Input 3 Quantity': 1,
                'Input 4 Item ID': None,
                'Input 4 Quantity': None,
                'Required Skill 1 ID': 'SKL-0013',
                'Required Skill 1 Level': 55,
                'Required Skill 2 ID': None,
                'Required Skill 2 Level': None,
                'Required Skill 3 ID': None,
                'Required Skill 3 Level': None,
            }
        )

    DATABASE.write_text(json.dumps(db, indent=2) + '\n')
    print('updated', DATABASE)


if __name__ == '__main__':
    main()
