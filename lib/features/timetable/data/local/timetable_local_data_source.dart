import 'dart:async';

import 'package:hive_ce/hive.dart';

import '../../../../core/constants/hive_boxes.dart';
import '../../domain/entities/class_session.dart';
import '../../domain/entities/period.dart';
import '../../domain/entities/timetable_entry.dart';
import 'timetable_adapters.dart';

/// Owns the timetable feature's Hive boxes.
///
/// The feature opens its own boxes rather than extending the core storage
/// service, so `core` never has to know about timetable models and each new
/// module can be added the same way.
class TimetableLocalDataSource {
  TimetableLocalDataSource();

  Box<Period>? _periods;
  Box<TimetableEntry>? _entries;
  Box<ClassSession>? _sessions;

  StreamController<void>? _changes;
  final List<StreamSubscription<BoxEvent>> _changeSubs =
      <StreamSubscription<BoxEvent>>[];

  bool get isInitialised => _periods != null;

  /// Opens the boxes. Assumes Hive itself has already been initialised by
  /// `LocalStorageService.init()`.
  Future<void> init() async {
    if (isInitialised) return;

    _registerAdapters();

    _periods = await Hive.openBox<Period>(HiveBoxes.periods);
    _entries = await Hive.openBox<TimetableEntry>(HiveBoxes.timetableEntries);
    _sessions = await Hive.openBox<ClassSession>(HiveBoxes.classSessions);
  }

  void _registerAdapters() {
    if (!Hive.isAdapterRegistered(HiveTypeIds.period)) {
      Hive.registerAdapter(PeriodAdapter());
    }
    if (!Hive.isAdapterRegistered(HiveTypeIds.timetableEntry)) {
      Hive.registerAdapter(TimetableEntryAdapter());
    }
    if (!Hive.isAdapterRegistered(HiveTypeIds.classSessionStatus)) {
      Hive.registerAdapter(ClassSessionStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(HiveTypeIds.classSession)) {
      Hive.registerAdapter(ClassSessionAdapter());
    }
  }

  Box<Period> get periodsBox => _require(_periods);
  Box<TimetableEntry> get entriesBox => _require(_entries);
  Box<ClassSession> get sessionsBox => _require(_sessions);

  // --- Reads (synchronous) ---------------------------------------------------

  List<Period> periods() {
    final List<Period> all = periodsBox.values.toList()
      ..sort((Period a, Period b) => a.sortOrder.compareTo(b.sortOrder));
    return all;
  }

  Period? periodById(String id) => periodsBox.get(id);

  List<TimetableEntry> allEntries() => entriesBox.values.toList(growable: false);

  List<TimetableEntry> entriesForWeekday(int weekday) => entriesBox.values
      .where((TimetableEntry e) => e.weekday == weekday)
      .toList(growable: false);

  TimetableEntry? entryById(String id) => entriesBox.get(id);

  ClassSession? sessionById(String id) => sessionsBox.get(id);

  List<ClassSession> allSessions() => sessionsBox.values.toList(growable: false);

  // --- Writes ---------------------------------------------------------------

  Future<void> putPeriods(List<Period> periods) async {
    await periodsBox.clear();
    await periodsBox.putAll(<String, Period>{
      for (final Period p in periods) p.id: p,
    });
  }

  Future<void> putEntry(TimetableEntry entry) =>
      entriesBox.put(entry.id, entry);

  Future<void> deleteEntry(String entryId) => entriesBox.delete(entryId);

  Future<void> putSession(ClassSession session) =>
      sessionsBox.put(session.id, session);

  Future<void> deleteSession(String sessionId) => sessionsBox.delete(sessionId);

  // Deliberately no bulk-clear method here. Wiping the boxes directly would
  // leave the outbox holding creates for records that no longer exist, so
  // clearing goes through `TimetableRepository.clearAllData`, which queues a
  // delete for each one.

  /// Drops session records older than [retention].
  ///
  /// Sessions accumulate one document per taught class. Trimming history keeps
  /// the local database small on a low-end device; the cloud copy remains the
  /// long-term record.
  Future<int> pruneSessionsBefore(DateTime cutoff) async {
    final List<String> stale = sessionsBox.values
        .where((ClassSession s) => s.date.isBefore(cutoff))
        .map((ClassSession s) => s.id)
        .toList(growable: false);
    if (stale.isNotEmpty) await sessionsBox.deleteAll(stale);
    return stale.length;
  }

  /// Emits on any change across the three boxes.
  ///
  /// One shared broadcast stream rather than a new one per caller: several
  /// providers watch this, and each fresh stream would otherwise attach its own
  /// three box listeners. The underlying listeners are attached on the first
  /// subscription and released when the last one leaves, so nothing keeps
  /// feeding a stream nobody is reading.
  Stream<void> watchChanges() {
    _changes ??= StreamController<void>.broadcast(
      onListen: _attachBoxListeners,
      onCancel: _detachBoxListeners,
    );
    return _changes!.stream;
  }

  void _attachBoxListeners() {
    if (_changeSubs.isNotEmpty) return;
    void emit(BoxEvent _) => _changes?.add(null);
    _changeSubs.addAll(<StreamSubscription<BoxEvent>>[
      periodsBox.watch().listen(emit),
      entriesBox.watch().listen(emit),
      sessionsBox.watch().listen(emit),
    ]);
  }

  /// Clears the list *before* awaiting, so a listener that re-subscribes during
  /// its own synchronous teardown sees an empty list and re-attaches properly.
  Future<void> _detachBoxListeners() async {
    final List<StreamSubscription<BoxEvent>> subs =
        List<StreamSubscription<BoxEvent>>.from(_changeSubs);
    _changeSubs.clear();

    for (final StreamSubscription<BoxEvent> sub in subs) {
      await sub.cancel();
    }
  }

  /// Closes the boxes and the change stream.
  ///
  /// Anyone already subscribed to [watchChanges] stops receiving events: the
  /// controller is closed, and a later `init()` creates a fresh one. Callers that
  /// reopen must re-subscribe. Only tests do this today; in the app the data
  /// source lives for the whole process.
  Future<void> close() async {
    await _detachBoxListeners();
    await _changes?.close();
    _changes = null;

    await _periods?.close();
    await _entries?.close();
    await _sessions?.close();
    _periods = null;
    _entries = null;
    _sessions = null;
  }

  Box<T> _require<T>(Box<T>? box) {
    if (box == null) {
      throw StateError(
        'TimetableLocalDataSource.init() must be awaited before use.',
      );
    }
    return box;
  }
}
