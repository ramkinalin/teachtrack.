/// The teacher using this device.
///
/// [id] is generated once on first setup and never changes. It is the value
/// stamped onto every timetable entry, which is what will let a headmaster view
/// answer "which class is handled by which teacher" once school-wide sync exists.
class TeacherProfile {
  const TeacherProfile({
    required this.id,
    required this.fullName,
    this.staffId = '',
    this.schoolName = '',
    this.classTeacherOf = '',
  });

  factory TeacherProfile.fromJson(Map<String, dynamic> json) => TeacherProfile(
        id: json['id'] as String,
        fullName: json['fullName'] as String? ?? '',
        staffId: json['staffId'] as String? ?? '',
        schoolName: json['schoolName'] as String? ?? '',
        classTeacherOf: json['classTeacherOf'] as String? ?? '',
      );

  final String id;
  final String fullName;

  /// Optional employee or staff number.
  final String staffId;

  final String schoolName;

  /// The section this teacher is class teacher of, e.g. `8B`. Empty means they
  /// are not a class teacher — modelled as an empty string rather than a
  /// separate boolean so the two can never disagree.
  final String classTeacherOf;

  bool get isClassTeacher => classTeacherOf.trim().isNotEmpty;

  /// Enough to identify the teacher in the UI.
  bool get isComplete => fullName.trim().isNotEmpty;

  /// `Mr Rao · Class teacher of 8B`
  String get displaySubtitle => isClassTeacher
      ? 'Class teacher of $classTeacherOf'
      : 'Subject teacher';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'fullName': fullName,
        'staffId': staffId,
        'schoolName': schoolName,
        'classTeacherOf': classTeacherOf,
      };

  TeacherProfile copyWith({
    String? fullName,
    String? staffId,
    String? schoolName,
    String? classTeacherOf,
  }) =>
      TeacherProfile(
        id: id,
        fullName: fullName ?? this.fullName,
        staffId: staffId ?? this.staffId,
        schoolName: schoolName ?? this.schoolName,
        classTeacherOf: classTeacherOf ?? this.classTeacherOf,
      );

  @override
  bool operator ==(Object other) =>
      other is TeacherProfile &&
      other.id == id &&
      other.fullName == fullName &&
      other.staffId == staffId &&
      other.schoolName == schoolName &&
      other.classTeacherOf == classTeacherOf;

  @override
  int get hashCode =>
      Object.hash(id, fullName, staffId, schoolName, classTeacherOf);

  @override
  String toString() => 'TeacherProfile($id, $fullName, $displaySubtitle)';
}
