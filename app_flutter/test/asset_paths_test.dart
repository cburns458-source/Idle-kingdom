import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/content/asset_paths.dart';
import 'package:ik_content/ik_content.dart';

/// The columns the icon heuristic reads; the rest of the row does not matter.
ItemRow item({
  required String itemId,
  required String displayName,
  String internalKey = '',
  String? category,
  String? subtype,
  String? iconAssetKey,
}) {
  return ItemRow(<String, Object?>{
    'Item ID': itemId,
    'Internal Key': internalKey,
    'Display Name': displayName,
    'Category': category,
    'Subtype': subtype,
    'Icon Asset Key': iconAssetKey,
  });
}

void main() {
  group('itemIconStem', () {
    test('uses the row icon key before the heuristic', () {
      expect(
        itemIconStem(
          item(itemId: 'ITEM-0003', displayName: 'Copper Ore', iconAssetKey: 'copper_ore'),
        ),
        'copper_ore',
      );
    });

    test('uses the pinned id before the heuristic', () {
      // Berries would otherwise fall through to the generic raw-food icon.
      expect(itemIconStem(item(itemId: 'ITEM-0028', displayName: 'Wild Berries')), 'berries');
      expect(itemIconStem(item(itemId: 'ITEM-0295', displayName: 'Spell')), 'spell');
    });

    test('draws Golden Spud with its own item icon', () {
      expect(
        itemIconStem(
          item(
            itemId: 'ITEM-0026',
            displayName: 'Golden Spud',
            internalKey: 'golden_spud',
            iconAssetKey: 'golden_spud',
          ),
        ),
        'golden_spud',
      );
    });

    test('maps platelegs to legs instead of chest', () {
      expect(
        itemIconStem(
          item(
            itemId: 'ITEM-0157',
            displayName: 'Iron Platelegs',
            internalKey: 'iron_platelegs',
            category: 'Armor',
            subtype: 'Platelegs',
          ),
        ),
        'legs',
      );
    });

    test('does not read explorer as ore', () {
      expect(
        itemIconStem(
          item(
            itemId: 'ITEM-0999',
            displayName: "Explorer's Pack",
            internalKey: 'explorer_s_pack',
            category: 'Armor',
            subtype: 'Specialist back item',
          ),
        ),
        'backpack',
      );
    });

    test('prefers the jewelry shape over the gem colour in the name', () {
      expect(
        itemIconStem(
          item(
            itemId: 'ITEM-0174',
            displayName: 'Sapphire Necklace',
            internalKey: 'sapphire_necklace',
            category: 'Jewelry',
            subtype: 'Necklace',
          ),
        ),
        'necklace',
      );
    });

    test('falls back to the generic icon', () {
      expect(itemIconStem(null), 'default');
      expect(itemIconStem(item(itemId: 'ITEM-9999', displayName: 'Curiosity')), 'default');
    });
  });

  test('paths carry the content prefix Flutter bundles', () {
    expect(goldIconPath(), 'content/assets/icons/items/item_gold.webp');
    expect(slotIconPath('SLOT-0003'), 'content/assets/icons/slots/slot_helmet.webp');
    expect(enemyAssetPath('ENM-0006'), 'content/assets/enemies/enm_dragon.webp');
    expect(enemyAssetPath('ENM-0020'), 'content/assets/enemies/enm_monk.webp');
    expect(actionAssetPath('ACN-0046'), 'content/assets/actions/acn_cut_cedar.webp');
    // Unmapped ids fall back rather than pointing at a missing bundle key.
    expect(enemyAssetPath('ENM-9999'), 'content/assets/enemies/enm_cow.webp');
    expect(workstationAssetPath(null), 'content/assets/workstations/ws_crafting_bench.webp');
    expect(npcAssetPath('NPC-0014'), 'content/assets/npc/npc_fennel.png');
    expect(npcAssetPath('NPC-0015'), 'content/assets/npc/npc_helge.png');
  });
}
