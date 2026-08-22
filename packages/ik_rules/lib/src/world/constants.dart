/// Map and location IDs the rules reference by name.
library;

/// Travel delay when database Base Duration is null. 0 = instant travel.
const num defaultTravelDurationMs = 0;

const String mainMapId = 'MAP-0001';
const String caveMapId = 'MAP-0002';
const String castleMapId = 'MAP-0003';
const String westMapId = 'MAP-0004';
const String eastMapId = 'MAP-0005';
const String townMapId = 'MAP-0006';
const String citadelMapId = 'MAP-0007';

const String caveEntranceId = 'LOC-0010';
const String caveMiningStoreId = 'LOC-0012';
const String castleGatewayId = 'LOC-0013';
const String castleCourtyardId = 'LOC-0014';
const String townGatewayId = 'LOC-0002';
const String citadelGatewayId = 'LOC-0027';
const String westHorizonId = 'LOC-0019';
const String eastHorizonId = 'LOC-0020';

/// Town district nodes (MAP-0006).
const String townKitchenId = 'LOC-0023';
const String townGeneralStoreId = 'LOC-0024';
const String townFoundryId = 'LOC-0025';
const String townApothecaryId = 'LOC-0026';
const String townBankId = 'LOC-0034';

/// Citadel hub nodes (MAP-0007).
const String citadelPlazaId = 'LOC-0028';
const String citadelMarketId = 'LOC-0029';
const String citadelProcessingId = 'LOC-0030';
const String citadelGatheringId = 'LOC-0031';
const String citadelCombatId = 'LOC-0032';
const String guildHallLocationId = 'LOC-0033';
const String citadelBankId = 'LOC-0035';

bool isFutureHorizonLocation(String locationId) {
  return locationId == westHorizonId || locationId == eastHorizonId;
}

String? adjacentMapForHorizon(String locationId) {
  if (locationId == westHorizonId) return westMapId;
  if (locationId == eastHorizonId) return eastMapId;
  return null;
}

bool isFutureRegionMapId(String? mapId) => mapId == westMapId || mapId == eastMapId;
