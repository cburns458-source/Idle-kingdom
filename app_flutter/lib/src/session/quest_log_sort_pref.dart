import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

/// Client-only quest journal sort. Default matches content / release order.
class QuestLogSortPref {
  QuestLogSortPref({this.storage, QuestLogSort? sort}) : _sort = sort ?? QuestLogSort.content;

  /// Not [saveStorageKey], so an export or a cloud write cannot pick this up.
  static const String storageKey = 'idle-kingdoms.client.quest-log-sort';

  final SaveStorage? storage;
  QuestLogSort _sort;

  QuestLogSort get sort => _sort;

  factory QuestLogSortPref.load(SaveStorage? storage) {
    final stored = storage?.getItem(storageKey);
    for (final option in QuestLogSort.values) {
      if (option.name == stored) {
        return QuestLogSortPref(storage: storage, sort: option);
      }
    }
    return QuestLogSortPref(storage: storage);
  }

  void setSort(QuestLogSort value) {
    _sort = value;
    storage?.setItem(storageKey, value.name);
  }
}
