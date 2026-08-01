import 'dart:async';

import 'package:hive_ce/hive.dart';

import '../../../../core/constants/hive_boxes.dart';
import '../../domain/entities/school_event.dart';
import 'event_adapters.dart';

/// Owns the events box.
///
/// Same pattern as the timetable: the feature opens its own box so `core` never
/// learns about feature models, and the change stream is shared and
/// reference-counted so listeners are attached only while something is watching.
class EventLocalDataSource {
  EventLocalDataSource();

  Box<SchoolEvent>? _events;

  StreamController<void>? _changes;
  StreamSubscription<BoxEvent>? _changeSub;

  bool get isInitialised => _events != null;

  /// Assumes Hive itself has already been initialised by `LocalStorageService`.
  Future<void> init() async {
    if (isInitialised) return;

    if (!Hive.isAdapterRegistered(HiveTypeIds.schoolEventCategory)) {
      Hive.registerAdapter(SchoolEventCategoryAdapter());
    }
    if (!Hive.isAdapterRegistered(HiveTypeIds.schoolEvent)) {
      Hive.registerAdapter(SchoolEventAdapter());
    }

    _events = await Hive.openBox<SchoolEvent>(HiveBoxes.schoolEvents);
  }

  Box<SchoolEvent> get box {
    final Box<SchoolEvent>? box = _events;
    if (box == null) {
      throw StateError('EventLocalDataSource.init() must be awaited before use.');
    }
    return box;
  }

  List<SchoolEvent> all() => box.values.toList(growable: false);

  SchoolEvent? byId(String id) => box.get(id);

  Future<void> put(SchoolEvent event) => box.put(event.id, event);

  Future<void> delete(String id) => box.delete(id);

  Future<void> clear() => box.clear();

  Stream<void> watchChanges() {
    _changes ??= StreamController<void>.broadcast(
      onListen: () {
        _changeSub ??= box.watch().listen((BoxEvent _) => _changes?.add(null));
      },
      // Cleared before awaiting: a listener that re-subscribes during its own
      // synchronous teardown would otherwise find the old subscription still set,
      // attach nothing, and be left with an unwatched box.
      // Not awaited: a broadcast controller's onCancel is `void Function()`, so
      // the cancel future cannot be returned from here.
      onCancel: () {
        final StreamSubscription<BoxEvent>? sub = _changeSub;
        _changeSub = null;
        unawaited(sub?.cancel());
      },
    );
    return _changes!.stream;
  }

  Future<void> close() async {
    await _changeSub?.cancel();
    _changeSub = null;
    await _changes?.close();
    _changes = null;
    await _events?.close();
    _events = null;
  }
}
