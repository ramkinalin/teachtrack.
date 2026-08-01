import 'dart:convert';

import '../../events/domain/entities/school_event.dart';
import '../../timetable/domain/entities/class_session.dart';
import '../../timetable/domain/entities/period.dart';
import '../../timetable/domain/entities/schedule_override.dart';
import '../../timetable/domain/entities/timetable_entry.dart';

/// Everything a teacher would hate to lose, in one versioned envelope.
///
/// There is no cloud, so this file is the only copy of the work that exists off
/// the phone. That makes two things non-negotiable: it must carry a version, and
/// parsing must refuse anything it does not fully understand rather than import
/// part of it. A half-restored timetable is worse than a failed restore, because
/// the teacher would not know which half.
class BackupPayload {
  const BackupPayload({
    required this.exportedAt,
    this.version = currentVersion,
    this.profile,
    this.subjects = const <String>[],
    this.periods = const <Period>[],
    this.entries = const <TimetableEntry>[],
    this.sessions = const <ClassSession>[],
    this.events = const <SchoolEvent>[],
    this.overrides = const <ScheduleOverride>[],
  });

  /// Bumped whenever the shape changes incompatibly. An older app reading a newer
  /// file refuses; a newer app reading an older file may migrate.
  static const int currentVersion = 1;

  /// Marks the file as ours, so a random JSON file picked by mistake is rejected
  /// with a sensible message instead of a parse error.
  static const String formatMarker = 'teachtrack.backup';

  final int version;
  final DateTime exportedAt;

  /// The teacher's own profile, as stored. `null` when setup never completed.
  final Map<String, dynamic>? profile;

  final List<String> subjects;
  final List<Period> periods;
  final List<TimetableEntry> entries;
  final List<ClassSession> sessions;
  final List<SchoolEvent> events;
  final List<ScheduleOverride> overrides;

  bool get isEmpty =>
      profile == null &&
      subjects.isEmpty &&
      periods.isEmpty &&
      entries.isEmpty &&
      sessions.isEmpty &&
      events.isEmpty &&
      overrides.isEmpty;

  /// A one-line summary for the confirmation dialog, so a teacher can see what
  /// they are about to restore before it happens.
  String get contentsSummary {
    final List<String> parts = <String>[
      if (entries.isNotEmpty) '${entries.length} classes',
      if (overrides.isNotEmpty) '${overrides.length} special schedules',
      if (events.isNotEmpty) '${events.length} events',
      if (sessions.isNotEmpty) '${sessions.length} marked lessons',
      if (subjects.isNotEmpty) '${subjects.length} subjects',
    ];
    return parts.isEmpty ? 'nothing' : parts.join(', ');
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'format': formatMarker,
        'version': version,
        'exportedAt': exportedAt.toIso8601String(),
        'profile': profile,
        'subjects': subjects,
        'periods': periods.map((Period p) => p.toJson()).toList(),
        'entries': entries.map((TimetableEntry e) => e.toJson()).toList(),
        'sessions': sessions.map((ClassSession s) => s.toJson()).toList(),
        'events': events.map((SchoolEvent e) => e.toJson()).toList(),
        'overrides':
            overrides.map((ScheduleOverride o) => o.toJson()).toList(),
      };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Parses [source], throwing [BackupFormatException] on anything unusable.
  ///
  /// Deliberately strict about the envelope and forgiving about individual
  /// records: a single malformed entry is skipped rather than failing the whole
  /// restore, because losing one class is recoverable and losing the file is not.
  static BackupPayload decode(String source) {
    final Object? raw;
    try {
      raw = jsonDecode(source);
    } on Object {
      throw const BackupFormatException(
        'That file is not a TeachTrack backup.',
      );
    }

    if (raw is! Map<String, dynamic>) {
      throw const BackupFormatException(
        'That file is not a TeachTrack backup.',
      );
    }

    if (raw['format'] != formatMarker) {
      throw const BackupFormatException(
        'That file is not a TeachTrack backup.',
      );
    }

    final Object? version = raw['version'];
    if (version is! int) {
      throw const BackupFormatException('That backup has no version.');
    }
    if (version > currentVersion) {
      throw BackupFormatException(
        'That backup was made by a newer version of TeachTrack. Update the app '
        'and try again.',
      );
    }

    final DateTime? exportedAt =
        DateTime.tryParse(raw['exportedAt'] as String? ?? '');
    if (exportedAt == null) {
      throw const BackupFormatException('That backup has no export date.');
    }

    return BackupPayload(
      version: version,
      exportedAt: exportedAt,
      profile: raw['profile'] is Map<String, dynamic>
          ? raw['profile'] as Map<String, dynamic>
          : null,
      subjects: _stringList(raw['subjects']),
      periods: _records(raw['periods'], Period.fromJson),
      entries: _records(raw['entries'], TimetableEntry.fromJson),
      sessions: _records(raw['sessions'], ClassSession.fromJson),
      events: _records(raw['events'], SchoolEvent.fromJson),
      overrides: _records(raw['overrides'], ScheduleOverride.fromJson),
    );
  }

  static List<String> _stringList(Object? raw) => raw is List
      ? raw.whereType<String>().toList(growable: false)
      : const <String>[];

  /// Maps a JSON list, dropping records that will not parse.
  static List<T> _records<T>(
    Object? raw,
    T Function(Map<String, dynamic>) parse,
  ) {
    if (raw is! List) return <T>[];

    final List<T> parsed = <T>[];
    for (final Object? item in raw) {
      if (item is! Map<String, dynamic>) continue;
      try {
        parsed.add(parse(item));
      } on Object {
        // One bad record must not cost the teacher the other two hundred.
        continue;
      }
    }
    return parsed;
  }

  @override
  String toString() =>
      'BackupPayload(v$version, $exportedAt, $contentsSummary)';
}

/// A backup file that cannot be used, with a message fit to show a teacher.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// How a restore treats what is already on the device.
enum RestoreMode {
  /// Wipe first, then import. What "restore my backup" normally means.
  replace,

  /// Keep what is there and add anything missing. For merging two devices.
  merge,
}

/// What a restore actually did.
class RestoreSummary {
  const RestoreSummary({
    this.entries = 0,
    this.sessions = 0,
    this.events = 0,
    this.overrides = 0,
    this.periods = 0,
    this.subjects = 0,
    this.skipped = 0,
    this.profileRestored = false,
  });

  final int entries;
  final int sessions;
  final int events;
  final int overrides;
  final int periods;
  final int subjects;

  /// Records the file contained that could not be written — a class whose slot
  /// was already taken, say. Reported rather than hidden.
  final int skipped;

  final bool profileRestored;

  int get total => entries + sessions + events + overrides + periods + subjects;

  String get summary {
    final List<String> parts = <String>[
      if (entries > 0) '$entries classes',
      if (overrides > 0) '$overrides schedules',
      if (events > 0) '$events events',
      if (sessions > 0) '$sessions marked lessons',
    ];
    if (parts.isEmpty) return 'Nothing to restore';
    final String base = 'Restored ${parts.join(', ')}';
    return skipped == 0 ? base : '$base · $skipped skipped';
  }

  @override
  String toString() => summary;
}
