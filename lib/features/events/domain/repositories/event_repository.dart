import '../../../../core/utils/result.dart';
import '../entities/school_event.dart';

/// Access to one-off dated events.
///
/// Reads are synchronous for the same reason as the timetable: the box is already
/// open, so a screen paints real content on its first frame.
abstract interface class EventRepository {
  /// Events from [from] onwards, soonest first, limited to the next [days].
  ///
  /// Past events are excluded rather than deleted — history stays available for
  /// a future term report.
  List<SchoolEvent> upcoming({required DateTime from, int days = 60});

  List<SchoolEvent> forDate(DateTime date);

  /// Everything, newest first. Used by history and export.
  List<SchoolEvent> all();

  SchoolEvent? byId(String id);

  Result<void> validate(SchoolEvent event);

  Future<Result<void>> upsert(SchoolEvent event);

  Future<Result<void>> delete(String id);

  Stream<void> watchChanges();
}
