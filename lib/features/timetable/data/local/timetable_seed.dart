import '../../../../core/utils/result.dart';
import '../../domain/entities/period.dart';
import '../../domain/entities/timetable_entry.dart';
import 'timetable_local_data_source.dart';

/// First-run data so the app is usable before a teacher enters anything.
///
/// The bell schedule is treated as a real default (most schools want editing,
/// not authoring, a period grid). The sample entries are development-only and
/// are skipped in release builds so a real user starts with an empty timetable.
abstract final class TimetableSeed {
  static const String p1 = 'p1';
  static const String p2 = 'p2';
  static const String morningBreak = 'break-am';
  static const String p3 = 'p3';
  static const String p4 = 'p4';
  static const String lunch = 'lunch';
  static const String p5 = 'p5';
  static const String p6 = 'p6';
  static const String p7 = 'p7';
  static const String p8 = 'p8';

  /// A conventional 8-period day with a morning break and lunch.
  static List<Period> defaultPeriods() => const <Period>[
        Period(
          id: p1,
          label: 'Period 1',
          startMinute: 8 * 60,
          endMinute: 8 * 60 + 45,
          sortOrder: 1,
        ),
        Period(
          id: p2,
          label: 'Period 2',
          startMinute: 8 * 60 + 45,
          endMinute: 9 * 60 + 30,
          sortOrder: 2,
        ),
        Period(
          id: morningBreak,
          label: 'Break',
          startMinute: 9 * 60 + 30,
          endMinute: 9 * 60 + 45,
          sortOrder: 3,
          isBreak: true,
        ),
        Period(
          id: p3,
          label: 'Period 3',
          startMinute: 9 * 60 + 45,
          endMinute: 10 * 60 + 30,
          sortOrder: 4,
        ),
        Period(
          id: p4,
          label: 'Period 4',
          startMinute: 10 * 60 + 30,
          endMinute: 11 * 60 + 15,
          sortOrder: 5,
        ),
        Period(
          id: lunch,
          label: 'Lunch',
          startMinute: 11 * 60 + 15,
          endMinute: 12 * 60,
          sortOrder: 6,
          isBreak: true,
        ),
        Period(
          id: p5,
          label: 'Period 5',
          startMinute: 12 * 60,
          endMinute: 12 * 60 + 45,
          sortOrder: 7,
        ),
        Period(
          id: p6,
          label: 'Period 6',
          startMinute: 12 * 60 + 45,
          endMinute: 13 * 60 + 30,
          sortOrder: 8,
        ),
        Period(
          id: p7,
          label: 'Period 7',
          startMinute: 13 * 60 + 30,
          endMinute: 14 * 60 + 15,
          sortOrder: 9,
        ),
        Period(
          id: p8,
          label: 'Period 8',
          startMinute: 14 * 60 + 15,
          endMinute: 15 * 60,
          sortOrder: 10,
        ),
      ];

  /// A realistic mixed week for one teacher, including PE lessons so the PE
  /// module has something to attach to later.
  static List<TimetableEntry> sampleWeek({String teacherId = ''}) {
    final List<TimetableEntry> entries = <TimetableEntry>[];

    void add(
      int weekday,
      String periodId,
      String subject,
      String classGroup, {
      String room = '',
      bool pe = false,
    }) {
      entries.add(
        TimetableEntry(
          id: 'seed-$weekday-$periodId',
          weekday: weekday,
          periodId: periodId,
          subject: subject,
          classGroup: classGroup,
          room: room,
          isPhysicalEducation: pe,
          teacherId: teacherId,
        ),
      );
    }

    add(DateTime.monday, p1, 'Mathematics', '8B', room: 'R-12');
    add(DateTime.monday, p2, 'Mathematics', '9A', room: 'R-12');
    add(DateTime.monday, p4, 'Physical Education', '7C',
        room: 'Main Field', pe: true);
    add(DateTime.monday, p6, 'Mathematics', '7C', room: 'R-08');

    add(DateTime.tuesday, p2, 'Mathematics', '8B', room: 'R-12');
    add(DateTime.tuesday, p3, 'Physical Education', '8B',
        room: 'Sports Hall', pe: true);
    add(DateTime.tuesday, p5, 'Mathematics', '9A', room: 'R-12');

    add(DateTime.wednesday, p1, 'Mathematics', '7C', room: 'R-08');
    add(DateTime.wednesday, p3, 'Mathematics', '8B', room: 'R-12');
    add(DateTime.wednesday, p7, 'Physical Education', '9A',
        room: 'Main Field', pe: true);

    add(DateTime.thursday, p2, 'Mathematics', '9A', room: 'R-12');
    add(DateTime.thursday, p4, 'Mathematics', '7C', room: 'R-08');
    add(DateTime.thursday, p6, 'Physical Education', '7C',
        room: 'Main Field', pe: true);

    add(DateTime.friday, p1, 'Mathematics', '8B', room: 'R-12');
    add(DateTime.friday, p3, 'Mathematics', '9A', room: 'R-12');
    add(DateTime.friday, p5, 'Physical Education', '8B',
        room: 'Sports Hall', pe: true);

    add(DateTime.saturday, p1, 'Mathematics', '9A', room: 'R-12');
    add(DateTime.saturday, p2, 'Games', '8B', room: 'Main Field', pe: true);

    return entries;
  }

  /// Ensures a bell schedule exists. Safe on every launch — it never overwrites
  /// a schedule the teacher has already adjusted.
  ///
  /// Sample classes are deliberately NOT seeded here. A new install must land on
  /// the real empty state so setup is visible; the demo week is available on
  /// demand from settings instead.
  static Future<void> ensurePeriods(TimetableLocalDataSource local) async {
    if (local.periodsBox.isEmpty) {
      await local.putPeriods(defaultPeriods());
    }
  }

  /// Adds the demo week through [upsert], skipping entries that already exist.
  ///
  /// Takes the repository's upsert rather than writing to the box directly, so
  /// demo data goes through the same validation and outbox path as a real entry.
  /// Anything the repository rejects — a slot a real class already holds — is
  /// simply skipped.
  ///
  /// Returns how many were added, so the caller can tell "loaded" from
  /// "already there".
  static Future<int> loadSampleWeek({
    required TimetableLocalDataSource local,
    required Future<Result<void>> Function(TimetableEntry entry) upsert,
    String teacherId = '',
  }) async {
    int added = 0;
    for (final TimetableEntry entry in sampleWeek(teacherId: teacherId)) {
      if (local.entryById(entry.id) != null) continue;
      final Result<void> result = await upsert(entry);
      if (result.isOk) added++;
    }
    return added;
  }
}
