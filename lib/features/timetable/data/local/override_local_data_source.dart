import 'dart:async';

import 'package:hive_ce/hive.dart';

import '../../../../core/constants/hive_boxes.dart';
import '../../../../core/utils/day_time.dart';
import '../../domain/entities/schedule_override.dart';
import 'override_adapters.dart';

/// Owns the schedule-overrides box.
class OverrideLocalDataSource {
  OverrideLocalDataSource();

  Box<ScheduleOverride>? _overrides;

  StreamController<void>? _changes;
  StreamSubscription<BoxEvent>? _changeSub;

  bool get isInitialised => _overrides != null;

  /// Assumes Hive itself has already been initialised by `LocalStorageService`.
  Future<void> init() async {
    if (isInitialised) return;

    if (!Hive.isAdapterRegistered(HiveTypeIds.scheduleOverrideKind)) {
      Hive.registerAdapter(ScheduleOverrideKindAdapter());
    }
    if (!Hive.isAdapterRegistered(HiveTypeIds.overrideSlot)) {
      Hive.registerAdapter(OverrideSlotAdapter());
    }
    if (!Hive.isAdapterRegistered(HiveTypeIds.scheduleOverride)) {
      Hive.registerAdapter(ScheduleOverrideAdapter());
    }

    _overrides =
        await Hive.openBox<ScheduleOverride>(HiveBoxes.scheduleOverrides);
  }

  Box<ScheduleOverride> get box {
    final Box<ScheduleOverride>? box = _overrides;
    if (box == null) {
      throw StateError(
        'OverrideLocalDataSource.init() must be awaited before use.',
      );
    }
    return box;
  }

  List<ScheduleOverride> all() {
    final List<ScheduleOverride> overrides = box.values.toList()
      ..sort((ScheduleOverride a, ScheduleOverride b) =>
          a.startDate.compareTo(b.startDate));
    return overrides;
  }

  ScheduleOverride? byId(String id) => box.get(id);

  /// The override covering [date].
  ///
  /// Validation forbids overlapping ranges, so at most one can match. If data
  /// ever does overlap — a restore from an older build, say — the earliest wins,
  /// which is at least deterministic.
  ScheduleOverride? covering(DateTime date) {
    final DateTime day = CalendarDay.dateOnly(date);
    for (final ScheduleOverride override in all()) {
      if (override.covers(day)) return override;
    }
    return null;
  }

  Future<void> put(ScheduleOverride override) =>
      box.put(override.id, override);

  Future<void> delete(String id) => box.delete(id);

  // No bulk clear here on purpose: wiping the box directly would leave the outbox
  // holding creates for overrides that no longer exist. Clearing goes through
  // `TimetableRepository.clearAllData`, which queues a delete for each.

  Stream<void> watchChanges() {
    _changes ??= StreamController<void>.broadcast(
      onListen: () {
        _changeSub ??= box.watch().listen((BoxEvent _) => _changes?.add(null));
      },
      // The field is cleared *before* awaiting the cancel, not after. Riverpod
      // disposes and rebuilds a provider synchronously, so a listener that
      // re-subscribes during its own teardown would hit `_changeSub ??=` while the
      // old value was still set, attach nothing, and then have the pending
      // microtask null it out — leaving the box unwatched and the day view frozen
      // for the rest of the session.
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
    await _overrides?.close();
    _overrides = null;
  }
}
