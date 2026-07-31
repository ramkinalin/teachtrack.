import '../../../../core/utils/day_time.dart';

/// What kind of thing is happening.
///
/// A class test, a match, a tournament, exam duty and a staff meeting are all the
/// same shape — something on a specific date, optionally at a specific time, with
/// a reminder. One entity with a category means adding the next kind costs one
/// enum value rather than a new table, screen and reminder pipeline.
enum SchoolEventCategory {
  classTest,
  match,
  tournament,
  examDuty,
  meeting,
  other;

  String get label => switch (this) {
        SchoolEventCategory.classTest => 'Class test',
        SchoolEventCategory.match => 'Match',
        SchoolEventCategory.tournament => 'Tournament',
        SchoolEventCategory.examDuty => 'Exam duty',
        SchoolEventCategory.meeting => 'Meeting',
        SchoolEventCategory.other => 'Other',
      };

  /// True for the categories a PE teacher cares about, which show venue and
  /// opponent fields instead of class and subject.
  bool get isFixture =>
      this == SchoolEventCategory.match || this == SchoolEventCategory.tournament;

  /// Sensible reminder lead times in minutes, chosen per category.
  ///
  /// A test wants warning the day before so a teacher can prepare the paper; a
  /// fixture wants the evening before plus a couple of hours to gather kit; a
  /// meeting only needs a nudge as it approaches.
  List<int> get defaultReminderLeadMinutes => switch (this) {
        SchoolEventCategory.classTest => const <int>[1440, 60],
        SchoolEventCategory.match => const <int>[1440, 120],
        SchoolEventCategory.tournament => const <int>[2880, 1440, 120],
        SchoolEventCategory.examDuty => const <int>[1440, 60],
        SchoolEventCategory.meeting => const <int>[30],
        SchoolEventCategory.other => const <int>[60],
      };
}

/// Something happening on one specific date.
///
/// Deliberately separate from [TimetableEntry], which is recurring. This is the
/// one-off primitive the app previously had no way to express.
class SchoolEvent {
  const SchoolEvent({
    required this.id,
    required this.date,
    required this.category,
    required this.title,
    this.classGroup = '',
    this.subject = '',
    this.startMinute,
    this.endMinute,
    this.location = '',
    this.opponent = '',
    this.notes = '',
    this.reminderLeadMinutes = const <int>[],
    this.teacherId = '',
    this.updatedAt,
  });

  factory SchoolEvent.fromJson(Map<String, dynamic> json) => SchoolEvent(
        id: json['id'] as String,
        date: DateTime.parse(json['date'] as String),
        category: SchoolEventCategory.values.firstWhere(
          (SchoolEventCategory c) => c.name == json['category'],
          orElse: () => SchoolEventCategory.other,
        ),
        title: json['title'] as String,
        classGroup: json['classGroup'] as String? ?? '',
        subject: json['subject'] as String? ?? '',
        startMinute: json['startMinute'] as int?,
        endMinute: json['endMinute'] as int?,
        location: json['location'] as String? ?? '',
        opponent: json['opponent'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        reminderLeadMinutes:
            (json['reminderLeadMinutes'] as List<dynamic>? ?? <dynamic>[])
                .whereType<int>()
                .toList(growable: false),
        teacherId: json['teacherId'] as String? ?? '',
        updatedAt: json['updatedAt'] == null
            ? null
            : DateTime.parse(json['updatedAt'] as String),
      );

  final String id;

  /// Date-only, local.
  final DateTime date;

  final SchoolEventCategory category;
  final String title;

  /// Empty when the event is not tied to one class.
  final String classGroup;

  /// Empty when the event is not tied to one subject.
  final String subject;

  /// Minutes since midnight. `null` means all-day.
  ///
  /// Stored as a plain time rather than a reference to a period on purpose: an
  /// event must not silently move when the bell schedule is adjusted, and it
  /// keeps this feature independent of the timetable module.
  final int? startMinute;
  final int? endMinute;

  /// Room, ground or venue.
  final String location;

  /// The other team. Only meaningful for fixtures.
  final String opponent;

  final String notes;

  /// Minutes before the event at which to remind. Empty means no reminder.
  final List<int> reminderLeadMinutes;

  final String teacherId;
  final DateTime? updatedAt;

  bool get isAllDay => startMinute == null;

  bool get hasReminders => reminderLeadMinutes.isNotEmpty;

  /// `09:30 – 11:00`, `09:30`, or `All day`.
  String get timeLabel {
    final int? start = startMinute;
    if (start == null) return 'All day';
    final int? end = endMinute;
    return end == null
        ? DayTime.format(start)
        : DayTime.formatRange(start, end);
  }

  /// `8B · Mathematics` for a test, `vs St. Xavier's · Main Field` for a match.
  String get subtitle {
    final List<String> parts = category.isFixture
        ? <String>[
            if (opponent.isNotEmpty) 'vs $opponent',
            if (location.isNotEmpty) location,
          ]
        : <String>[
            if (classGroup.isNotEmpty) classGroup,
            if (subject.isNotEmpty) subject,
            if (location.isNotEmpty) location,
          ];
    return parts.join(' · ');
  }

  /// Absolute instants at which reminders should fire.
  ///
  /// The lead is subtracted inside the `DateTime` constructor's minute field,
  /// which normalises negative values back across day boundaries. That keeps the
  /// result at the intended *wall-clock* time: `anchor.subtract(Duration(...))`
  /// would be elapsed-time arithmetic, so a day-before reminder for a 10:00 event
  /// would land at 09:00 or 11:00 across a daylight-saving change.
  ///
  /// All-day events anchor at 08:00, so a "1 day before" lead arrives at 08:00
  /// the previous day rather than at midnight.
  List<DateTime> reminderTimes() {
    final int anchorMinute = startMinute ?? 8 * 60;

    return reminderLeadMinutes
        .map(
          (int lead) => DateTime(
            date.year,
            date.month,
            date.day,
            0,
            anchorMinute - lead,
          ),
        )
        .toList(growable: false);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'date': date.toIso8601String(),
        'category': category.name,
        'title': title,
        'classGroup': classGroup,
        'subject': subject,
        'startMinute': startMinute,
        'endMinute': endMinute,
        'location': location,
        'opponent': opponent,
        'notes': notes,
        'reminderLeadMinutes': reminderLeadMinutes,
        'teacherId': teacherId,
        'updatedAt': updatedAt?.toIso8601String(),
      };

  SchoolEvent copyWith({
    DateTime? date,
    SchoolEventCategory? category,
    String? title,
    String? classGroup,
    String? subject,
    int? startMinute,
    bool clearStartMinute = false,
    int? endMinute,
    bool clearEndMinute = false,
    String? location,
    String? opponent,
    String? notes,
    List<int>? reminderLeadMinutes,
    String? teacherId,
    DateTime? updatedAt,
  }) =>
      SchoolEvent(
        id: id,
        date: date ?? this.date,
        category: category ?? this.category,
        title: title ?? this.title,
        classGroup: classGroup ?? this.classGroup,
        subject: subject ?? this.subject,
        startMinute:
            clearStartMinute ? null : (startMinute ?? this.startMinute),
        endMinute: clearEndMinute ? null : (endMinute ?? this.endMinute),
        location: location ?? this.location,
        opponent: opponent ?? this.opponent,
        notes: notes ?? this.notes,
        reminderLeadMinutes: reminderLeadMinutes ?? this.reminderLeadMinutes,
        teacherId: teacherId ?? this.teacherId,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  String toString() =>
      'SchoolEvent($id, ${category.name}, $title, ${CalendarDay.key(date)})';
}
