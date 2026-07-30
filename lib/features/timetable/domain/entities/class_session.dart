import '../../../../core/utils/day_time.dart';

enum ClassSessionStatus { scheduled, completed, cancelled }

/// What actually happened to one timetable entry on one specific date.
///
/// Sessions are only written when a teacher acts. A class nobody taps has no
/// session record at all and is implicitly [ClassSessionStatus.scheduled] — so a
/// normal week costs zero writes, which is the single biggest Firestore saving
/// in this module.
class ClassSession {
  const ClassSession({
    required this.id,
    required this.entryId,
    required this.date,
    required this.status,
    this.updatedAt,
    this.note = '',
  });

  factory ClassSession.fromJson(Map<String, dynamic> json) => ClassSession(
        id: json['id'] as String,
        entryId: json['entryId'] as String,
        date: DateTime.parse(json['date'] as String),
        status: ClassSessionStatus.values.firstWhere(
          (ClassSessionStatus s) => s.name == json['status'],
          orElse: () => ClassSessionStatus.scheduled,
        ),
        updatedAt: json['updatedAt'] == null
            ? null
            : DateTime.parse(json['updatedAt'] as String),
        note: json['note'] as String? ?? '',
      );

  /// Deterministic: `2026-07-30_entry-abc`.
  ///
  /// Building the id from date and entry rather than a random uuid means a
  /// completion recorded on a sports field maps to exactly one Firestore
  /// document, so replaying the same write twice is harmless.
  static String buildId(DateTime date, String entryId) =>
      '${CalendarDay.key(date)}_$entryId';

  final String id;
  final String entryId;

  /// Date-only, local.
  final DateTime date;

  final ClassSessionStatus status;
  final DateTime? updatedAt;
  final String note;

  bool get isCompleted => status == ClassSessionStatus.completed;
  bool get isCancelled => status == ClassSessionStatus.cancelled;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'entryId': entryId,
        'date': date.toIso8601String(),
        'status': status.name,
        'updatedAt': updatedAt?.toIso8601String(),
        'note': note,
      };

  ClassSession copyWith({
    ClassSessionStatus? status,
    DateTime? updatedAt,
    String? note,
  }) =>
      ClassSession(
        id: id,
        entryId: entryId,
        date: date,
        status: status ?? this.status,
        updatedAt: updatedAt ?? this.updatedAt,
        note: note ?? this.note,
      );

  @override
  bool operator ==(Object other) =>
      other is ClassSession &&
      other.id == id &&
      other.entryId == entryId &&
      other.date == date &&
      other.status == status &&
      other.updatedAt == updatedAt &&
      other.note == note;

  @override
  int get hashCode => Object.hash(id, entryId, date, status, updatedAt, note);

  @override
  String toString() => 'ClassSession($id, ${status.name})';
}
