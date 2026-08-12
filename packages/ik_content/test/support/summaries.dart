import 'package:ik_content/ik_content.dart';

Map<String, Object?> issuesOutput(GameDatabase db) => <String, Object?>{
  'issues': validateDatabase(db).map((issue) => issue.toJson()).toList(),
};

Map<String, Object?> tableCounts(GameDatabase db) => <String, Object?>{
  for (final table in databaseTables) table: db.rowsOf(table).length,
};

List<String> idsOf(List<Map<String, Object?>> rows, String idColumn) =>
    rows.map((row) => '${row[idColumn] ?? ''}').toList();

Map<String, Object?> prepareOutput(Object? raw) {
  try {
    final loaded = prepareDatabase(raw);
    return <String, Object?>{
      'ok': true,
      'needsDataCount': loaded.needsDataCount,
      'issueCount': loaded.issues.length,
      'launchCounts': tableCounts(loaded.launch),
      'sourceCounts': tableCounts(loaded.source),
    };
  } on DatabaseValidationException catch (error) {
    return <String, Object?>{'ok': false, 'error': error.message};
  } on DatabaseShapeException catch (error) {
    return <String, Object?>{'ok': false, 'error': error.message};
  }
}

Map<String, Object?> shapeOutput(Object? raw) {
  try {
    assertGameDatabaseShape(raw);
    return <String, Object?>{'error': null};
  } on DatabaseShapeException catch (error) {
    return <String, Object?>{'error': error.message};
  }
}

Map<String, Object?> _groupSummary<T extends DbRow>(Map<String, List<T>> group, String idColumn) {
  return <String, Object?>{
    for (final entry in group.entries)
      entry.key: entry.value.map((row) => '${row.raw[idColumn] ?? ''}').toList(),
  };
}

/// Full index contents, for the small synthetic databases.
Map<String, Object?> indexSummary(DatabaseIndexes indexes) => <String, Object?>{
  'configByKey': indexes.configByKey.keys.toList(),
  'skillsById': indexes.skillsById.keys.toList(),
  'skillDisplayNames': indexes.skillsById.values.map((row) => row.displayName).toList(),
  'locationsById': indexes.locationsById.keys.toList(),
  'itemsById': indexes.itemsById.keys.toList(),
  'mapsById': indexes.mapsById.keys.toList(),
  'activitiesById': indexes.activitiesById.keys.toList(),
  'actionsById': indexes.actionsById.keys.toList(),
  'facilitiesByLocationId': _groupSummary(indexes.facilitiesByLocationId, 'Facility ID'),
  'activitiesByLocationId': _groupSummary(indexes.activitiesByLocationId, 'Activity ID'),
  'npcsByLocationId': _groupSummary(indexes.npcsByLocationId, 'NPC ID'),
  'shopsByLocationId': _groupSummary(indexes.shopsByLocationId, 'Shop ID'),
  'poolEntriesByPoolId': _groupSummary(indexes.poolEntriesByPoolId, 'Pool Entry ID'),
  'rewardEntriesByTableId': _groupSummary(indexes.rewardEntriesByTableId, 'Reward Entry ID'),
  'locationSearchesByLocationId': _groupSummary(indexes.locationSearchesByLocationId, 'Search ID'),
  'byTableIdCounts': <String, Object?>{
    for (final entry in indexes.byTableId.entries) entry.key: entry.value.length,
  },
};

Map<String, Object?> _ends(List<String> keys) => <String, Object?>{
  'count': keys.length,
  'first': keys.take(3).toList(),
  'last': keys.skip(keys.length < 3 ? 0 : keys.length - 3).toList(),
};

Map<String, Object?> _groupEnds<T extends DbRow>(Map<String, List<T>> group) {
  final keys = group.keys.toList();
  return <String, Object?>{
    'count': group.length,
    'first': keys.take(3).toList(),
    'last': keys.skip(keys.length < 3 ? 0 : keys.length - 3).toList(),
    'sizes': <String, Object?>{for (final entry in group.entries) entry.key: entry.value.length},
  };
}

/// Cardinality plus the ends of each key sequence, for the real database.
Map<String, Object?> compactIndexSummary(DatabaseIndexes indexes) => <String, Object?>{
  'configByKey': _ends(indexes.configByKey.keys.toList()),
  'skillsById': _ends(indexes.skillsById.keys.toList()),
  'locationsById': _ends(indexes.locationsById.keys.toList()),
  'itemsById': _ends(indexes.itemsById.keys.toList()),
  'mapsById': _ends(indexes.mapsById.keys.toList()),
  'activitiesById': _ends(indexes.activitiesById.keys.toList()),
  'actionsById': _ends(indexes.actionsById.keys.toList()),
  'facilitiesByLocationId': _groupEnds(indexes.facilitiesByLocationId),
  'activitiesByLocationId': _groupEnds(indexes.activitiesByLocationId),
  'npcsByLocationId': _groupEnds(indexes.npcsByLocationId),
  'shopsByLocationId': _groupEnds(indexes.shopsByLocationId),
  'poolEntriesByPoolId': _groupEnds(indexes.poolEntriesByPoolId),
  'rewardEntriesByTableId': _groupEnds(indexes.rewardEntriesByTableId),
  'locationSearchesByLocationId': _groupEnds(indexes.locationSearchesByLocationId),
  'byTableIdCounts': <String, Object?>{
    for (final entry in indexes.byTableId.entries) entry.key: entry.value.length,
  },
};
