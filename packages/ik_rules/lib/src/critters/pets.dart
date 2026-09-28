import '../cosmetics/cosmetics.dart';
import '../save/generated/save_models.dart';

/// Critter ID → Pet Cosmetic ID. First collection unlocks the matching pet.
const Map<String, String> critterPetCosmeticIds = <String, String>{
  'CRT-0001': 'COS-0004',
  'CRT-0002': 'COS-0005',
  'CRT-0003': 'COS-0006',
  'CRT-0004': 'COS-0007',
  'CRT-0005': 'COS-0008',
  'CRT-0006': 'COS-0009',
  'CRT-0007': 'COS-0010',
  'CRT-0008': 'COS-0011',
  'CRT-0009': 'COS-0012',
};

String? petCosmeticIdForCritter(String critterId) => critterPetCosmeticIds[critterId];

/// Critter internal key used for asset paths, keyed by pet cosmetic.
const Map<String, String> petCosmeticCritterKeys = <String, String>{
  'COS-0004': 'chick',
  'COS-0005': 'rat',
  'COS-0006': 'entling',
  'COS-0007': 'mole',
  'COS-0008': 'squirrel',
  'COS-0009': 'crab',
  'COS-0010': 'pika',
  'COS-0011': 'raccoon',
  'COS-0012': 'baby_dragon',
};

String? critterKeyForPetCosmetic(String cosmeticId) => petCosmeticCritterKeys[cosmeticId];

/// Unlock pets for every Critter already in the collection (migration / catch-up).
PlayerSave grantPetsForCollectedCritters(PlayerSave save) {
  var next = save;
  for (final row in save.critterCollections) {
    if (row.count < 1) continue;
    final cosmeticId = petCosmeticIdForCritter(row.critterId);
    if (cosmeticId == null) continue;
    next = grantCosmetic(next, cosmeticId).save;
  }
  return next;
}
