import '../../../../core/utils/day_time.dart';

/// A slot in the school's bell schedule, shared by every timetable entry.
///
/// Periods are defined once per school. A timetable entry references a period by
/// id and carries no times of its own, so changing a bell time is a single edit
/// and every entry document stays small.
class Period {
  const Period({
    required this.id,
    required this.label,
    required this.startMinute,
    required this.endMinute,
    required this.sortOrder,
    this.isBreak = false,
  });

  factory Period.fromJson(Map<String, dynamic> json) => Period(
        id: json['id'] as String,
        label: json['label'] as String,
        startMinute: json['startMinute'] as int,
        endMinute: json['endMinute'] as int,
        sortOrder: json['sortOrder'] as int,
        isBreak: json['isBreak'] as bool? ?? false,
      );

  final String id;
  final String label;

  /// Minutes since midnight. See [DayTime].
  final int startMinute;
  final int endMinute;

  /// Display order, independent of times so irregular schedules still sort.
  final int sortOrder;

  /// Breaks and lunch occupy the grid but are never taught or marked complete.
  final bool isBreak;

  Duration get duration => Duration(minutes: endMinute - startMinute);

  bool containsMinute(int minuteOfDay) =>
      minuteOfDay >= startMinute && minuteOfDay < endMinute;

  bool isBefore(int minuteOfDay) => endMinute <= minuteOfDay;

  bool isAfter(int minuteOfDay) => startMinute > minuteOfDay;

  String get timeRangeLabel => DayTime.formatRange(startMinute, endMinute);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'label': label,
        'startMinute': startMinute,
        'endMinute': endMinute,
        'sortOrder': sortOrder,
        'isBreak': isBreak,
      };

  Period copyWith({
    String? label,
    int? startMinute,
    int? endMinute,
    int? sortOrder,
    bool? isBreak,
  }) =>
      Period(
        id: id,
        label: label ?? this.label,
        startMinute: startMinute ?? this.startMinute,
        endMinute: endMinute ?? this.endMinute,
        sortOrder: sortOrder ?? this.sortOrder,
        isBreak: isBreak ?? this.isBreak,
      );

  @override
  bool operator ==(Object other) =>
      other is Period &&
      other.id == id &&
      other.label == label &&
      other.startMinute == startMinute &&
      other.endMinute == endMinute &&
      other.sortOrder == sortOrder &&
      other.isBreak == isBreak;

  @override
  int get hashCode =>
      Object.hash(id, label, startMinute, endMinute, sortOrder, isBreak);

  @override
  String toString() => 'Period($id, $label, $timeRangeLabel)';
}
