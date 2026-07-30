/// One recurring class in a teacher's weekly timetable.
///
/// Carries no times: the referenced [periodId] owns them. Identity is
/// `(weekday, periodId)` per teacher, which is what the editor enforces.
class TimetableEntry {
  const TimetableEntry({
    required this.id,
    required this.weekday,
    required this.periodId,
    required this.subject,
    required this.classGroup,
    this.room = '',
    this.isPhysicalEducation = false,
    this.notes = '',
  });

  factory TimetableEntry.fromJson(Map<String, dynamic> json) => TimetableEntry(
        id: json['id'] as String,
        weekday: json['weekday'] as int,
        periodId: json['periodId'] as String,
        subject: json['subject'] as String,
        classGroup: json['classGroup'] as String,
        room: json['room'] as String? ?? '',
        isPhysicalEducation: json['isPhysicalEducation'] as bool? ?? false,
        notes: json['notes'] as String? ?? '',
      );

  final String id;

  /// `DateTime.monday`..`DateTime.sunday`.
  final int weekday;

  final String periodId;

  final String subject;

  /// Class or section taught, e.g. `8B`.
  final String classGroup;

  final String room;

  /// Flags the lesson for the PE module (rosters, equipment) to hook into later
  /// without needing a parallel entry type.
  final bool isPhysicalEducation;

  final String notes;

  /// Slot identity used for conflict detection.
  String get slotKey => '$weekday:$periodId';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'weekday': weekday,
        'periodId': periodId,
        'subject': subject,
        'classGroup': classGroup,
        'room': room,
        'isPhysicalEducation': isPhysicalEducation,
        'notes': notes,
      };

  TimetableEntry copyWith({
    int? weekday,
    String? periodId,
    String? subject,
    String? classGroup,
    String? room,
    bool? isPhysicalEducation,
    String? notes,
  }) =>
      TimetableEntry(
        id: id,
        weekday: weekday ?? this.weekday,
        periodId: periodId ?? this.periodId,
        subject: subject ?? this.subject,
        classGroup: classGroup ?? this.classGroup,
        room: room ?? this.room,
        isPhysicalEducation: isPhysicalEducation ?? this.isPhysicalEducation,
        notes: notes ?? this.notes,
      );

  @override
  bool operator ==(Object other) =>
      other is TimetableEntry &&
      other.id == id &&
      other.weekday == weekday &&
      other.periodId == periodId &&
      other.subject == subject &&
      other.classGroup == classGroup &&
      other.room == room &&
      other.isPhysicalEducation == isPhysicalEducation &&
      other.notes == notes;

  @override
  int get hashCode => Object.hash(
        id,
        weekday,
        periodId,
        subject,
        classGroup,
        room,
        isPhysicalEducation,
        notes,
      );

  @override
  String toString() =>
      'TimetableEntry($id, weekday: $weekday, period: $periodId, $subject)';
}
