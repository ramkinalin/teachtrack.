import '../../../../core/utils/day_time.dart';

/// Why the normal timetable does not apply on these dates.
/// Deliberately no `halfDay`: an override replaces the *whole* day, so a half day
/// would mean re-entering every surviving morning lesson as a sitting. Offering
/// the option without a mechanism behind it would be a trap. Use `special` and
/// list what actually happens.
enum ScheduleOverrideKind {
  exam,
  holiday,
  special;

  String get label => switch (this) {
        ScheduleOverrideKind.exam => 'Exams',
        ScheduleOverrideKind.holiday => 'Holiday',
        ScheduleOverrideKind.special => 'Special schedule',
      };

  /// A holiday has nothing to show, so it carries no slots at all.
  bool get allowsSlots => this != ScheduleOverrideKind.holiday;
}

/// One sitting on one date during an override.
///
/// Dated individually rather than following a weekly pattern, because every day
/// of an exam week has a different paper — which is exactly why the recurring
/// timetable cannot express this.
class OverrideSlot {
  const OverrideSlot({
    required this.id,
    required this.date,
    required this.startMinute,
    required this.title,
    this.endMinute,
    this.classGroup = '',
    this.subject = '',
    this.location = '',
    this.isInvigilating = false,
    this.isMySubject = false,
    this.notes = '',
  });

  factory OverrideSlot.fromJson(Map<String, dynamic> json) => OverrideSlot(
        id: json['id'] as String,
        date: DateTime.parse(json['date'] as String),
        startMinute: json['startMinute'] as int,
        title: json['title'] as String,
        endMinute: json['endMinute'] as int?,
        classGroup: json['classGroup'] as String? ?? '',
        subject: json['subject'] as String? ?? '',
        location: json['location'] as String? ?? '',
        isInvigilating: json['isInvigilating'] as bool? ?? false,
        isMySubject: json['isMySubject'] as bool? ?? false,
        notes: json['notes'] as String? ?? '',
      );

  final String id;

  /// Date-only, local. Must fall inside its override's range.
  final DateTime date;

  final int startMinute;
  final int? endMinute;

  /// What is being sat, e.g. `Mathematics paper 1`.
  final String title;

  final String classGroup;
  final String subject;

  /// Hall or room.
  final String location;

  /// This teacher is on duty for it — the obligation half.
  final bool isInvigilating;

  /// It is this teacher's own subject being examined — the planning half.
  final bool isMySubject;

  final String notes;

  String get timeRangeLabel => endMinute == null
      ? DayTime.format(startMinute)
      : DayTime.formatRange(startMinute, endMinute!);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'date': date.toIso8601String(),
        'startMinute': startMinute,
        'endMinute': endMinute,
        'title': title,
        'classGroup': classGroup,
        'subject': subject,
        'location': location,
        'isInvigilating': isInvigilating,
        'isMySubject': isMySubject,
        'notes': notes,
      };

  OverrideSlot copyWith({
    DateTime? date,
    int? startMinute,
    int? endMinute,
    bool clearEndMinute = false,
    String? title,
    String? classGroup,
    String? subject,
    String? location,
    bool? isInvigilating,
    bool? isMySubject,
    String? notes,
  }) =>
      OverrideSlot(
        id: id,
        date: date ?? this.date,
        startMinute: startMinute ?? this.startMinute,
        endMinute: clearEndMinute ? null : (endMinute ?? this.endMinute),
        title: title ?? this.title,
        classGroup: classGroup ?? this.classGroup,
        subject: subject ?? this.subject,
        location: location ?? this.location,
        isInvigilating: isInvigilating ?? this.isInvigilating,
        isMySubject: isMySubject ?? this.isMySubject,
        notes: notes ?? this.notes,
      );

  @override
  String toString() =>
      'OverrideSlot($id, ${CalendarDay.key(date)}, $timeRangeLabel, $title)';
}

/// A date range on which the normal weekly timetable is replaced.
///
/// Exam weeks, holidays, half days and sports days are the same idea: for these
/// dates, look here instead of at the weekday pattern. Building it once retires
/// all four.
class ScheduleOverride {
  const ScheduleOverride({
    required this.id,
    required this.name,
    required this.kind,
    required this.startDate,
    required this.endDate,
    this.slots = const <OverrideSlot>[],
    this.notes = '',
    this.teacherId = '',
    this.updatedAt,
  });

  factory ScheduleOverride.fromJson(Map<String, dynamic> json) =>
      ScheduleOverride(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: ScheduleOverrideKind.values.firstWhere(
          (ScheduleOverrideKind k) => k.name == json['kind'],
          orElse: () => ScheduleOverrideKind.special,
        ),
        startDate: DateTime.parse(json['startDate'] as String),
        endDate: DateTime.parse(json['endDate'] as String),
        slots: (json['slots'] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(OverrideSlot.fromJson)
            .toList(growable: false),
        notes: json['notes'] as String? ?? '',
        teacherId: json['teacherId'] as String? ?? '',
        updatedAt: json['updatedAt'] == null
            ? null
            : DateTime.parse(json['updatedAt'] as String),
      );

  final String id;

  /// What a teacher would call it: "Half-yearly exams", "Diwali break".
  final String name;

  final ScheduleOverrideKind kind;

  /// Both date-only and local. Inclusive at both ends.
  final DateTime startDate;
  final DateTime endDate;

  final List<OverrideSlot> slots;
  final String notes;
  final String teacherId;
  final DateTime? updatedAt;

  bool get isHoliday => kind == ScheduleOverrideKind.holiday;

  /// Inclusive on both ends, comparing calendar days only.
  bool covers(DateTime date) {
    final DateTime day = CalendarDay.dateOnly(date);
    return !day.isBefore(startDate) && !day.isAfter(endDate);
  }

  bool overlaps(ScheduleOverride other) =>
      !startDate.isAfter(other.endDate) && !endDate.isBefore(other.startDate);

  /// Differenced in UTC: two local midnights are 23 or 25 hours apart across a
  /// daylight-saving change, which would report a two-day range as one day.
  int get dayCount =>
      DateTime.utc(endDate.year, endDate.month, endDate.day)
          .difference(DateTime.utc(startDate.year, startDate.month, startDate.day))
          .inDays +
      1;

  /// Slots on one date, earliest first.
  List<OverrideSlot> slotsOn(DateTime date) {
    final DateTime day = CalendarDay.dateOnly(date);
    final List<OverrideSlot> matching = slots
        .where((OverrideSlot s) => CalendarDay.isSameDay(s.date, day))
        .toList()
      ..sort((OverrideSlot a, OverrideSlot b) =>
          a.startMinute.compareTo(b.startMinute));
    return matching;
  }

  /// `Mon 2026-08-10 – Fri 2026-08-14`, or a single date when it is one day.
  String get rangeLabel {
    if (dayCount == 1) {
      return '${CalendarDay.shortLabel(startDate.weekday)} '
          '${CalendarDay.key(startDate)}';
    }
    return '${CalendarDay.key(startDate)} – ${CalendarDay.key(endDate)}';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'kind': kind.name,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'slots':
            slots.map((OverrideSlot s) => s.toJson()).toList(growable: false),
        'notes': notes,
        'teacherId': teacherId,
        'updatedAt': updatedAt?.toIso8601String(),
      };

  ScheduleOverride copyWith({
    String? name,
    ScheduleOverrideKind? kind,
    DateTime? startDate,
    DateTime? endDate,
    List<OverrideSlot>? slots,
    String? notes,
    String? teacherId,
    DateTime? updatedAt,
  }) =>
      ScheduleOverride(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
        slots: slots ?? this.slots,
        notes: notes ?? this.notes,
        teacherId: teacherId ?? this.teacherId,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  String toString() =>
      'ScheduleOverride($id, ${kind.name}, $name, $rangeLabel, '
      '${slots.length} slots)';
}
