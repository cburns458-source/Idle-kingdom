import '../cosmetics/cosmetics.dart';
import '../save/generated/save_models.dart';

/// Critter ID → Pet Cosmetic ID. First collection unlocks the matching pet.
const Map<String, String> critterPetCosmeticIds = <String, String>{
  'CRT-0001': 'COS-0004',
  'CRT-0002': 'COS-0005',
  'CRT-0003': 'COS-0006',
  'CRT-0004': 'COS-0007',
};

String? petCosmeticIdForCritter(String critterId) => critterPetCosmeticIds[critterId];

/// Critter internal key used for asset paths, keyed by pet cosmetic.
const Map<String, String> petCosmeticCritterKeys = <String, String>{
  'COS-0004': 'fly',
  'COS-0005': 'rat',
  'COS-0006': 'entling',
  'COS-0007': 'mole',
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
