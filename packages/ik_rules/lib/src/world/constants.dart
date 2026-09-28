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
const String forestMapId = 'MAP-0008';
const String depthsMapId = 'MAP-0009';
const String mountainsMapId = 'MAP-0010';

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

/// Ancient Forest woodland (MAP-0008).
const String forestGatewayId = 'LOC-0039';
const String forestPathId = 'LOC-0040';
const String oldEntGroveId = 'LOC-0018';
const String starlightGladeId = 'LOC-0044';
const String smallClearingId = 'LOC-0050';
const String mirrorLakeId = 'LOC-0051';
const String throughTheThicketQuestId = 'QST-0010';
const String forestPathVinesActivityId = 'ACT-0048';
const String smallClearingVinesActivityId = 'ACT-0077';
const String starlightVinesActivityId = 'ACT-0078';
const String mirrorLakeVinesActivityId = 'ACT-0079';
const String oldEntGroveVinesActivityId = 'ACT-0082';
const String forestPathVinesStepId = 'QSTP-0025';
const String smallClearingVinesStepId = 'QSTP-0027';
const String starlightVinesStepId = 'QSTP-0028';
const String mirrorLakeVinesStepId = 'QSTP-0029';
const String oldEntGroveVinesStepId = 'QSTP-0036';

class ThicketVineActivitySpec {
  const ThicketVineActivitySpec({
    required this.locationId,
    required this.stepId,
    required this.persistAfterQuest,
  });

  final String locationId;
  final String stepId;
  final bool persistAfterQuest;
}

/// Chop vines nodes for Through the Thicket. Path stays after completion; the rest do not.
const Map<String, ThicketVineActivitySpec> thicketVineActivities =
    <String, ThicketVineActivitySpec>{
      forestPathVinesActivityId: ThicketVineActivitySpec(
        locationId: forestPathId,
        stepId: forestPathVinesStepId,
        persistAfterQuest: true,
      ),
      smallClearingVinesActivityId: ThicketVineActivitySpec(
        locationId: smallClearingId,
        stepId: smallClearingVinesStepId,
        persistAfterQuest: false,
      ),
      starlightVinesActivityId: ThicketVineActivitySpec(
        locationId: starlightGladeId,
        stepId: starlightVinesStepId,
        persistAfterQuest: false,
      ),
      mirrorLakeVinesActivityId: ThicketVineActivitySpec(
        locationId: mirrorLakeId,
        stepId: mirrorLakeVinesStepId,
        persistAfterQuest: false,
      ),
      oldEntGroveVinesActivityId: ThicketVineActivitySpec(
        locationId: oldEntGroveId,
        stepId: oldEntGroveVinesStepId,
        persistAfterQuest: false,
      ),
    };

String leftVinesFlag(String locationId) => 'leftVines:$locationId';

const List<String> thicketCompletionLocationIds = <String>[
  smallClearingId,
  starlightGladeId,
  mirrorLakeId,
  oldEntGroveId,
];

/// The Depths underwater (MAP-0009).
const String sunkenApproachId = 'LOC-0041';
const String theDepthsId = 'LOC-0042';
const String theShallowsId = 'LOC-0043';

/// Mountains range (MAP-0010).
const String mountainsGatewayId = 'LOC-0006';
const String theSlopesId = 'LOC-0046';
const String thePeakId = 'LOC-0047';
const String badlandsId = 'LOC-0048';
const String giantCampId = 'LOC-0049';

bool isFutureHorizonLocation(String locationId) {
  return locationId == westHorizonId || locationId == eastHorizonId;
}

String? adjacentMapForHorizon(String locationId) {
  if (locationId == westHorizonId) return westMapId;
  if (locationId == eastHorizonId) return eastMapId;
  return null;
}

bool isFutureRegionMapId(String? mapId) => mapId == westMapId || mapId == eastMapId;
